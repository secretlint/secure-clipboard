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

@Test func extractTextFromImage() async throws {
    let image = createImageWithText("Hello World Test Text")
    let detector = ImageSecretDetector()
    let extractedText = try await detector.extractText(from: image)
    #expect(extractedText.isEmpty == false)
}

@Test func detectNoSecretInCleanImage() async throws {
    let image = createImageWithText("This is just normal text")
    let scanner = makeScannerWithBinary()
    let detector = ImageSecretDetector(scanner: scanner)
    let result = try await detector.detect(image: image)
    #expect(result.hasSecrets == false)
}

private func createImageWithText(_ text: String) -> NSImage {
    let size = NSSize(width: 400, height: 100)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(origin: .zero, size: size))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24),
        .foregroundColor: NSColor.black
    ]
    text.draw(at: NSPoint(x: 10, y: 40), withAttributes: attributes)
    image.unlockFocus()
    return image
}
