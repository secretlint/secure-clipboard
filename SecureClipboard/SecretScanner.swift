import Foundation

struct ScanResult {
    let hasSecrets: Bool
    let maskedText: String
    let originalText: String
}

actor SecretScanner {
    private let binaryPath: String
    private let configJSON: String

    init() {
        if let resourcePath = Bundle.main.resourcePath {
            self.binaryPath = "\(resourcePath)/Resources/secretlint"
        } else {
            self.binaryPath = "secretlint"
        }
        self.configJSON = """
        {"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}
        """
    }

    init(binaryPath: String, configJSON: String? = nil) {
        self.binaryPath = binaryPath
        self.configJSON = configJSON ?? """
        {"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}
        """
    }

    func scan(text: String) async throws -> ScanResult {
        let rawOutput = try await runSecretlint(input: text, format: "mask-result")
        // secretlint may append a trailing newline to output; strip it if input doesn't have one
        let maskedText: String
        if !text.hasSuffix("\n") && rawOutput.hasSuffix("\n") {
            maskedText = String(rawOutput.dropLast())
        } else {
            maskedText = rawOutput
        }
        let hasSecrets = maskedText != text
        return ScanResult(
            hasSecrets: hasSecrets,
            maskedText: maskedText,
            originalText: text
        )
    }

    private func runSecretlint(input: String, format: String) async throws -> String {
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

        // exit code 0 = no secrets, 1 = secrets found (both are valid)
        // exit code 2+ = error
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
