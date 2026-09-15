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

private func makeScannerWithConfig(_ config: AppConfig) -> SecretScanner {
    let testFilePath = URL(fileURLWithPath: #filePath)
    let repoRoot = testFilePath
        .deletingLastPathComponent() // SecureClipboardTests/
        .deletingLastPathComponent() // repo root
    let binaryPath = repoRoot
        .appendingPathComponent("SecureClipboard")
        .appendingPathComponent("Resources")
        .appendingPathComponent("secretlint")
        .path
    return SecretScanner(binaryPath: binaryPath, configProvider: { config })
}

@Test func scanTextWithReplacePattern() async throws {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "token-value",
                pattern: "/[0-9a-f]{32}/",
                action: .replace,
                replacement: "[REDACTED]"
            )
        ]
    )
    let scanner = makeScannerWithConfig(config)
    let secret = "0123456789abcdef0123456789abcdef"
    let input = "PROXMOX_TOKEN_SECRET=\(secret)"
    let result = try await scanner.scan(text: input)
    #expect(result.hasSecrets == true)
    #expect(result.maskedText == "PROXMOX_TOKEN_SECRET=[REDACTED]")
    #expect(result.originalText == input)
    #expect(result.maskedText.contains(secret) == false)
}

@Test func scanTextWithReplaceAndPresetSecret() async throws {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: [
            .init(
                name: "token-value",
                pattern: "/[0-9a-f]{32}/",
                action: .replace,
                replacement: "[REDACTED]"
            )
        ]
    )
    let scanner = makeScannerWithConfig(config)
    let secret = "0123456789abcdef0123456789abcdef"
    let slack = slackTokenText()
    let input = "HEX=\(secret) SLACK=\(slack)"
    let result = try await scanner.scan(text: input)
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains(secret) == false)
    #expect(result.maskedText.contains("[REDACTED]"))
    #expect(result.maskedText.contains(slack) == false)
    #expect(result.maskedText.contains("*"))
}

@Test func scanTextWithReplacePresetSecretAndTrailingNewline() async throws {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: [
            .init(
                name: "api-token",
                pattern: "/(?<=API_TOKEN=)[0-9a-f]{32}/",
                action: .replace,
                replacement: "[REDACTED]"
            )
        ]
    )
    let scanner = makeScannerWithConfig(config)
    let hex = "0123456789abcdef0123456789abcdef"
    let slackPrefix = "xoxb"
    let slack = "\(slackPrefix)-123456789012-1234567890123-ABCDEFGHIJKLMNOPabcdefgh"
    let input = "API_TOKEN=\(hex) SLACK=\(slack)\n"

    let result = try await scanner.scan(text: input)

    #expect(result.hasSecrets == true)
    #expect(result.originalText == input)
    // Custom replace preserved.
    #expect(result.maskedText.hasPrefix("API_TOKEN=[REDACTED] SLACK="))
    #expect(result.maskedText.contains(hex) == false)
    // secretlint mask preserved.
    #expect(result.maskedText.contains(slack) == false)
    #expect(result.maskedText.contains("*"))
    // Trailing newline preserved.
    #expect(result.maskedText.hasSuffix("\n"))
}

@Test func scanTextWithReplaceNoMatch() async throws {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "token-value",
                pattern: "/[0-9a-f]{32}/",
                action: .replace,
                replacement: "[REDACTED]"
            )
        ]
    )
    let scanner = makeScannerWithConfig(config)
    let result = try await scanner.scan(text: "no secrets here")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "no secrets here")
}
