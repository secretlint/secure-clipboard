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
}
