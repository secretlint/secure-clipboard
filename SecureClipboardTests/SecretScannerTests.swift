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

// MARK: - Process lifecycle regression tests

/// Writes a temporary executable shell script and returns its URL plus the temp directory.
private func makeExecutableScript(_ body: String) throws -> (url: URL, directory: URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("secureclipboard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("mock-secretlint")
    try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, directory)
}

private func processExists(_ pid: pid_t) -> Bool {
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

private func waitForPidFile(at url: URL, timeout: TimeInterval = 2) -> pid_t? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return pid
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
}

private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval = 2) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !processExists(pid) { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

/// A child that never exits must be terminated by the timeout, and the scan must
/// return within a bounded time rather than waiting forever.
@Test func scanTerminatesHangingProcessOnTimeout() async throws {
    let (scriptURL, directory) = try makeExecutableScript(
        "echo $$ > \"$(dirname \"$0\")/pid\"\nwhile true; do :; done"
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let scanner = SecretScanner(binaryPath: scriptURL.path, configJSON: "{}", timeout: 0.5)

    let start = Date()
    var didTimeOut = false
    do {
        _ = try await scanner.scan(text: "hello world")
        Issue.record("Expected scan to throw a timeout error")
    } catch let error as SecretScannerError {
        if case .timeout = error {
            didTimeOut = true
        } else {
            Issue.record("Expected timeout, got \(error)")
        }
    }
    let elapsed = Date().timeIntervalSince(start)

    #expect(didTimeOut)
    #expect(elapsed < 5.0, "scan should return within a bounded time")

    let pid = try #require(waitForPidFile(at: directory.appendingPathComponent("pid")))
    #expect(waitForProcessExit(pid), "hung child should be terminated and reaped")
}

/// A child that ignores SIGTERM must be escalated to SIGKILL and reaped, and the
/// scan must still return within a bounded time.
@Test func scanForceKillsProcessThatIgnoresTermination() async throws {
    let (scriptURL, directory) = try makeExecutableScript(
        "echo $$ > \"$(dirname \"$0\")/pid\"\ntrap '' TERM\nwhile true; do :; done"
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let scanner = SecretScanner(binaryPath: scriptURL.path, configJSON: "{}", timeout: 0.5)

    let start = Date()
    var didTimeOut = false
    do {
        _ = try await scanner.scan(text: "hello world")
        Issue.record("Expected scan to throw a timeout error")
    } catch let error as SecretScannerError {
        if case .timeout = error {
            didTimeOut = true
        } else {
            Issue.record("Expected timeout, got \(error)")
        }
    }
    let elapsed = Date().timeIntervalSince(start)

    #expect(didTimeOut)
    #expect(elapsed < 5.0, "scan should return within a bounded time")

    let pid = try #require(waitForPidFile(at: directory.appendingPathComponent("pid")))
    #expect(waitForProcessExit(pid), "child ignoring SIGTERM should be SIGKILLed and reaped")
}

/// A child producing far more output than the pipe buffer can hold must not deadlock,
/// which proves stdout/stderr are drained while the process runs.
@Test func scanDrainsLargeStdoutAndStderrWithoutDeadlock() async throws {
    let (scriptURL, directory) = try makeExecutableScript(
        "head -c 2000000 /dev/zero | tr '\\0' 'x'\nhead -c 2000000 /dev/zero | tr '\\0' 'e' 1>&2"
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let scanner = SecretScanner(binaryPath: scriptURL.path, configJSON: "{}", timeout: 15)

    let result = try await scanner.scan(text: "hello world")
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.count >= 2_000_000)
}

/// Existing non-zero-exit handling (status > 1) must be preserved.
@Test func scanStillReportsFailureForNonZeroExit() async throws {
    let (scriptURL, directory) = try makeExecutableScript("echo 'secretlint boom' 1>&2\nexit 2")
    defer { try? FileManager.default.removeItem(at: directory) }

    let scanner = SecretScanner(binaryPath: scriptURL.path, configJSON: "{}", timeout: 10)

    do {
        _ = try await scanner.scan(text: "hello world")
        Issue.record("Expected scan to throw a scanFailed error")
    } catch let error as SecretScannerError {
        guard case .scanFailed(let message) = error else {
            Issue.record("Expected scanFailed, got \(error)")
            return
        }
        #expect(message.contains("boom"))
    }
}
