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
    private let binaryPath: String
    private let fixedConfigJSON: String?

    init() {
        if let url = Bundle.module.url(forResource: "secretlint", withExtension: nil, subdirectory: "Resources") {
            self.binaryPath = url.path
        } else if let resourcePath = Bundle.main.resourcePath {
            self.binaryPath = "\(resourcePath)/secretlint"
        } else {
            self.binaryPath = "secretlint"
        }
        self.fixedConfigJSON = nil
    }

    init(binaryPath: String, configJSON: String? = nil) {
        self.binaryPath = binaryPath
        self.fixedConfigJSON = configJSON
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--stdinFileName", "clipboard.txt",
            "--format", format,
            "--secretlintrcJSON", configJSON
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let inputData = Data(input.utf8)
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? input

        if process.terminationStatus > 1 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SecretScannerError.scanFailed(errorOutput)
        }

        return output
    }
}

enum SecretScannerError: Error {
    case scanFailed(String)
}
