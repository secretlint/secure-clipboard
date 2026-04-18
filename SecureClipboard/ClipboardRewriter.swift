import AppKit

struct ClipboardRewriter {
    @discardableResult
    func rewriteText(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    func rewriteImageWithRedaction(original: NSImage, secretBounds: [CGRect]) -> Int {
        let redactedImage: NSImage
        if secretBounds.isEmpty {
            redactedImage = createWarningImage(size: original.size)
        } else {
            redactedImage = redactRegions(image: original, regions: secretBounds)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([redactedImage])
        return pasteboard.changeCount
    }

    @discardableResult
    func rewriteImageWithWarning(originalSize: NSSize) -> Int {
        let warningImage = createWarningImage(size: originalSize)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([warningImage])
        return pasteboard.changeCount
    }

    /// Draw red rectangles over secret regions on the original image
    private func redactRegions(image: NSImage, regions: [CGRect]) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()

        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: image.size))

        // Draw red overlay on each secret region with padding
        let padding: CGFloat = 4
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
        for region in regions {
            let paddedRect = NSRect(
                x: region.origin.x - padding,
                y: region.origin.y - padding,
                width: region.size.width + padding * 2,
                height: region.size.height + padding * 2
            )
            NSBezierPath.fill(paddedRect)
        }

        result.unlockFocus()
        return result
    }

    private func createWarningImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))

        let text = "SECRET DETECTED"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: min(size.width, size.height) * 0.1),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        return image
    }
}
