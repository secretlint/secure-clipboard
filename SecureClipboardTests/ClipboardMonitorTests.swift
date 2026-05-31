import Testing
import AppKit
@testable import SecureClipboard

// These tests use NSPasteboard.general which is shared process-wide.
// Serialization prevents parallel tests from interfering with changeCount.
@Suite(.serialized)
struct ClipboardMonitorTests {
    @Test func detectsClipboardChange() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        let initialChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString("test", forType: .string)

        let hasChanged = monitor.hasClipboardChanged(since: initialChangeCount)
        #expect(hasChanged == true)
    }

    @Test func skipsOwnChanges() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString("test", forType: .string)

        let currentChangeCount = pasteboard.changeCount
        monitor.recordOwnChange(changeCount: currentChangeCount)

        let hasChanged = monitor.hasClipboardChanged(since: currentChangeCount - 1)
        #expect(hasChanged == false)
    }

    @Test func clearsWhenChangeCountMatches() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString("stale content", forType: .string)
        let captured = pasteboard.changeCount

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: captured)

        #expect(pasteboard.string(forType: .string) == nil)
        // クリア書き込みは自己書き込みとして記録され、再検出されない
        #expect(monitor.hasClipboardChanged(since: captured) == false)
    }

    @Test func doesNotClearWhenChangeCountStale() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let stale = pasteboard.changeCount

        // captured より後に新しい内容がコピーされた状況を再現
        pasteboard.clearContents()
        pasteboard.setString("new content", forType: .string)

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: stale)

        // 最新の内容は消えない（no-op）
        #expect(pasteboard.string(forType: .string) == "new content")
    }

    @Test func doesNotClearWhenAlreadyEmpty() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        let captured = pasteboard.changeCount

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: captured)

        // 空のまま no-op（changeCount を無駄に変動させない）
        #expect(pasteboard.changeCount == captured)
    }
}
