import Testing
import AppKit
@testable import SecureClipboard

@Test func rewriteTextReturnsNewChangeCount() {
    let rewriter = ClipboardRewriter()
    let before = NSPasteboard.general.changeCount
    let changeCount = rewriter.rewriteText("masked text")
    #expect(changeCount > before)
}

@Test func rewriteImageReturnsNewChangeCount() {
    let rewriter = ClipboardRewriter()
    let before = NSPasteboard.general.changeCount
    let changeCount = rewriter.rewriteImageWithWarning(originalSize: NSSize(width: 100, height: 100))
    #expect(changeCount > before)
}
