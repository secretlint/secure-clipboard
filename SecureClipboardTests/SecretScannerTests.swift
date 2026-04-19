import Foundation
import Testing
@testable import SecureClipboard

private func makeScannerWithBinary(configJSON: String? = nil) -> SecretScanner {
    // The binary is at SecureClipboard/Resources/secretlint relative to the repo root.
    // Use #filePath to locate the repo root from the test file path.
    let testFilePath = URL(fileURLWithPath: #filePath)
    let repoRoot = testFilePath
        .deletingLastPathComponent() // SecureClipboardTests/
        .deletingLastPathComponent() // repo root
    let binaryPath = repoRoot
        .appendingPathComponent("SecureClipboard")
        .appendingPathComponent("Resources")
        .appendingPathComponent("secretlint")
        .path
    return SecretScanner(binaryPath: binaryPath, configJSON: configJSON)
}

/// Build a Slack token string at runtime to avoid triggering the pre-commit secretlint check.
private func slackTokenText() -> String {
    // secretlint-disable
    let prefix = "xoxb"
    return "my token is \(prefix)-123456789012-1234567890123-ABCDEFGHIJKLMNOPabcdefgh"
}

@Test func scanTextWithNoSecret() async throws {
    let scanner = makeScannerWithBinary()
    let result = try await scanner.scan(text: "hello world")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "hello world")
}

/// Verify that Japanese regex patterns with dakuten characters (e.g. ガ, ビ, ゾ)
/// work correctly despite macOS Process.arguments converting to NFD.
@Test func scanTextWithJapanesePattern() async throws {
    let configJSON = #"{"rules":[{"id":"@secretlint/secretlint-rule-pattern","options":{"patterns":[{"name":"test-dakuten","pattern":"/ダミーデータ/i"}]}}]}"#
    let scanner = makeScannerWithBinary(configJSON: configJSON)
    let result = try await scanner.scan(text: "これはダミーデータです")
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains("*"))
}

@Test func scanTextWithSlackToken() async throws {
    let scanner = makeScannerWithBinary()
    let secretText = slackTokenText()
    let result = try await scanner.scan(text: secretText)
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains("*"))
}
