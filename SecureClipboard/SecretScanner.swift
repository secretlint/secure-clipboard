import Foundation

enum ScanAction {
    case mask(maskedText: String)
    case discard(patternName: String)
    case none
}

struct ScanResult {
    let action: ScanAction
    let originalText: String

    var hasSecrets: Bool {
        switch action {
        case .none: return false
        case .mask, .discard: return true
        }
    }

    var maskedText: String {
        switch action {
        case .mask(let text): return text
        case .discard, .none: return originalText
        }
    }
}

actor SecretScanner {
    /// Maximum time a secretlint invocation may run before it is terminated.
    /// Generous for clipboard-sized input while still bounded.
    static let defaultTimeout: TimeInterval = 10

    private let binaryPath: String
    private let fixedConfigJSON: String?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = SecretScanner.defaultTimeout) {
        if let url = Bundle.module.url(forResource: "secretlint", withExtension: nil, subdirectory: "Resources") {
            self.binaryPath = url.path
        } else if let resourcePath = Bundle.main.resourcePath {
            self.binaryPath = "\(resourcePath)/secretlint"
        } else {
            self.binaryPath = "secretlint"
        }
        self.fixedConfigJSON = nil
        self.timeout = timeout
    }

    init(binaryPath: String, configJSON: String? = nil, timeout: TimeInterval = SecretScanner.defaultTimeout) {
        self.binaryPath = binaryPath
        self.fixedConfigJSON = configJSON
        self.timeout = timeout
    }

    func scan(text: String) async throws -> ScanResult {
        let currentConfig = AppConfig.load()

        // Check discard patterns first (Swift-side regex, no secretlint call needed)
        if fixedConfigJSON == nil, let matched = currentConfig.matchesDiscardPattern(text) {
            return ScanResult(action: .discard(patternName: matched.name), originalText: text)
        }

        // Run secretlint with --format=mask-result
        let currentConfigJSON = fixedConfigJSON ?? currentConfig.secretlintrcJSON()
        let rawOutput = try await runSecretlint(input: text, format: "mask-result", configJSON: currentConfigJSON)
        // Normalize trailing whitespace for comparison — secretlint may strip trailing newlines
        let normalizedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedOutput != normalizedInput {
            // Real masking happened — reconstruct with original trailing whitespace
            let maskedText: String
            if !text.hasSuffix("\n") && rawOutput.hasSuffix("\n") {
                maskedText = String(rawOutput.dropLast())
            } else {
                maskedText = rawOutput
            }
            return ScanResult(action: .mask(maskedText: maskedText), originalText: text)
        }
        return ScanResult(action: .none, originalText: text)
    }

    private func runSecretlint(input: String, format: String, configJSON: String) async throws -> String {
        // Write config to a temporary file instead of passing via --secretlintrcJSON argument.
        // macOS Process.arguments converts strings to NFD (Unicode decomposed form),
        // which breaks regex patterns containing characters like ビ (NFC) → ヒ+゙ (NFD).
        let tmpConfigPath = NSTemporaryDirectory() + "secretlintrc-\(UUID().uuidString).json"
        try configJSON.write(toFile: tmpConfigPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpConfigPath) }

        let binaryPath = self.binaryPath
        let timeout = self.timeout
        let inputData = Data(input.utf8)
        let arguments = [
            "--stdinFileName", "clipboard.txt",
            "--format", format,
            "--secretlintrc", tmpConfigPath
        ]

        // Run the blocking process management off the actor's executor so a slow or
        // hung child cannot tie up the cooperative thread pool for the whole timeout.
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runProcess(
                        binaryPath: binaryPath,
                        arguments: arguments,
                        input: inputData,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let output = String(data: result.stdout, encoding: .utf8) ?? input

        if result.status > 1 {
            let errorOutput = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
            throw SecretScannerError.scanFailed(errorOutput)
        }

        return output
    }

    private struct ProcessResult: Sendable {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    /// Thread-safe accumulator for data read from a pipe on a background queue.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func store(_ data: Data) {
            lock.lock()
            storage = data
            lock.unlock()
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Runs a child process to completion, draining stdout/stderr concurrently so
    /// neither pipe can fill and block the child. If the process outlives `timeout`
    /// it is terminated (SIGTERM, then SIGKILL) and `SecretScannerError.timeout` is thrown.
    private static func runProcess(
        binaryPath: String,
        arguments: [String],
        input: Data,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let drainGroup = DispatchGroup()

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exitSemaphore.signal() }

        try process.run()

        // Drain both output pipes concurrently while the child runs so a full pipe
        // buffer can never block the child. Process closes the parent's write end on
        // launch, so each reader observes EOF once the child is gone.
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        inputPipe.fileHandleForWriting.write(input)
        inputPipe.fileHandleForWriting.closeFile()

        let timedOut = exitSemaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            terminate(process: process, exitSemaphore: exitSemaphore)
        }

        // The child has now been reaped — either it exited on its own or terminate()
        // confirmed it — so both pipes are guaranteed to reach EOF. Waiting without a
        // timeout ensures we never return partial stdout/stderr.
        drainGroup.wait()

        if timedOut {
            throw SecretScannerError.timeout(timeout)
        }

        return ProcessResult(
            stdout: stdoutBox.data,
            stderr: stderrBox.data,
            status: process.terminationStatus
        )
    }

    /// Terminates a still-running process. SIGTERM is attempted first; if the process
    /// has not been reaped after a grace period, SIGKILL is sent. SIGKILL cannot be
    /// caught, so the final wait is unbounded and only returns once the child has
    /// actually exited and been reaped.
    private static func terminate(process: Process, exitSemaphore: DispatchSemaphore) {
        process.terminate()
        if exitSemaphore.wait(timeout: .now() + 1) == .success {
            return
        }

        kill(process.processIdentifier, SIGKILL)
        exitSemaphore.wait()
    }
}

enum SecretScannerError: Error {
    case scanFailed(String)
    case timeout(TimeInterval)
}
