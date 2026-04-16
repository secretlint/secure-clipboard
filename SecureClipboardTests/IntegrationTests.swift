import Testing
import AppKit
@testable import SecureClipboard

private func makeScannerWithBinary() -> SecretScanner {
    let testFilePath = URL(fileURLWithPath: #filePath)
    let repoRoot = testFilePath
        .deletingLastPathComponent() // SecureClipboardTests/
        .deletingLastPathComponent() // repo root
    let binaryPath = repoRoot
        .appendingPathComponent("SecureClipboard")
        .appendingPathComponent("Resources")
        .appendingPathComponent("secretlint")
        .path
    return SecretScanner(binaryPath: binaryPath)
}

/// Build a Slack token string at runtime to avoid triggering the pre-commit secretlint check.
private func slackTokenText() -> String {
    // secretlint-disable
    let prefix = "xoxb"
    return "\(prefix)-123456789012-1234567890123-ABCDEFGHIJKLMNOPabcdefgh"
}

@Test func endToEndTextMasking() async throws {
    let scanner = makeScannerWithBinary()
    let rewriter = ClipboardRewriter()

    let slackToken = slackTokenText()
    let testText = "my token is \(slackToken)"

    // Scan
    let result = try await scanner.scan(text: testText)
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains(slackToken) == false)
    #expect(result.maskedText.contains("*"))

    // Rewrite clipboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(testText, forType: .string)

    rewriter.rewriteText(result.maskedText)

    let clipboardContent = pasteboard.string(forType: .string)
    #expect(clipboardContent == result.maskedText)
    #expect(clipboardContent?.contains(slackToken) == false)
}

@Test func noFalsePositiveOnNormalText() async throws {
    let scanner = makeScannerWithBinary()
    let result = try await scanner.scan(text: "Hello, this is a normal message with no secrets.")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "Hello, this is a normal message with no secrets.")
}
