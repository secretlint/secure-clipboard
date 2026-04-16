import Testing
import AppKit
@testable import SecureClipboard

@Test func rewriteTextUpdatesClipboard() {
    let rewriter = ClipboardRewriter()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("original text", forType: .string)

    let changeCount = rewriter.rewriteText("masked text")

    let result = pasteboard.string(forType: .string)
    #expect(result == "masked text")
    #expect(changeCount == pasteboard.changeCount)
}

@Test func rewriteImageUpdatesClipboard() {
    let rewriter = ClipboardRewriter()
    let pasteboard = NSPasteboard.general

    let changeCount = rewriter.rewriteImageWithWarning(originalSize: NSSize(width: 100, height: 100))

    #expect(changeCount == pasteboard.changeCount)
    let types = pasteboard.types ?? []
    #expect(types.contains(.tiff) || types.contains(.png))
}
