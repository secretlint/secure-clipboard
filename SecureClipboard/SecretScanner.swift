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

    /// Load config on every call so file changes are picked up without restart
    private var config: AppConfig {
        AppConfig.load()
    }

    private var configJSON: String {
        if let fixed = fixedConfigJSON { return fixed }
        return config.secretlintrcJSON()
    }

    func scan(text: String) async throws -> ScanResult {
        let currentConfig = config
        let currentConfigJSON = fixedConfigJSON ?? currentConfig.secretlintrcJSON()

        // Step 1: Run secretlint with --format=json to detect matches
        let jsonOutput = try await runSecretlint(input: text, format: "json", configJSON: currentConfigJSON)

        // Parse JSON to find matched rule names
        let matchedNames = parseMatchedNames(jsonOutput)

        if matchedNames.isEmpty {
            return ScanResult(action: .none, originalText: text)
        }

        // Step 2: Check if any matched name is a discard pattern
        let discardPatternNames = Set(
            (currentConfig.patterns ?? [])
                .filter { $0.action == .discard }
                .map(\.name)
        )
        for name in matchedNames {
            if discardPatternNames.contains(name) {
                return ScanResult(action: .discard(patternName: name), originalText: text)
            }
        }

        // Step 3: Mask — run secretlint with --format=mask-result
        let rawOutput = try await runSecretlint(input: text, format: "mask-result", configJSON: currentConfigJSON)
        let maskedText: String
        if !text.hasSuffix("\n") && rawOutput.hasSuffix("\n") {
            maskedText = String(rawOutput.dropLast())
        } else {
            maskedText = rawOutput
        }

        if maskedText != text {
            return ScanResult(action: .mask(maskedText: maskedText), originalText: text)
        }
        return ScanResult(action: .none, originalText: text)
    }

    /// Parse secretlint JSON output to extract matched rule/pattern names
    private func parseMatchedNames(_ jsonOutput: String) -> [String] {
        guard let data = jsonOutput.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var names: [String] = []
        for result in results {
            guard let messages = result["messages"] as? [[String: Any]] else { continue }
            for message in messages {
                // ruleId format: "@secretlint/secretlint-rule-pattern > name" or just "ruleId"
                if let ruleId = message["ruleId"] as? String {
                    // Extract pattern name from "parent > name" format
                    if ruleId.contains(" > ") {
                        let parts = ruleId.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
                        if let name = parts.last {
                            names.append(name)
                        }
                    } else {
                        names.append(ruleId)
                    }
                }
            }
        }
        return names
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
