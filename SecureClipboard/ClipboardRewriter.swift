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

    /// Blur secret regions on the original image so they blend naturally
    private func redactRegions(image: NSImage, regions: [CGRect]) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return createWarningImage(size: image.size)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let blurRadius: CGFloat = 10
        let padding: CGFloat = 2

        // Create a fully blurred version of the image
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return createWarningImage(size: image.size)
        }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        guard let blurredImage = blurFilter.outputImage else {
            return createWarningImage(size: image.size)
        }

        // Composite: use blurred version for secret regions, original for the rest
        var composited = ciImage
        let imageHeight = CGFloat(cgImage.height)

        for region in regions {
            // Vision coordinates have origin at bottom-left, CIImage too — matches directly
            // But we need to convert from NSImage coordinates to pixel coordinates
            let scaleX = CGFloat(cgImage.width) / image.size.width
            let scaleY = CGFloat(cgImage.height) / image.size.height
            let pixelRect = CGRect(
                x: (region.origin.x - padding) * scaleX,
                y: (region.origin.y - padding) * scaleY,
                width: (region.size.width + padding * 2) * scaleX,
                height: (region.size.height + padding * 2) * scaleY
            )

            // Create a mask for this region
            let maskImage = CIImage(color: .white).cropped(to: pixelRect)
            let invertMask = CIImage(color: .white).cropped(to: ciImage.extent)

            // Blend: blurred in the masked region, original elsewhere
            if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                blendFilter.setValue(blurredImage, forKey: kCIInputImageKey)
                blendFilter.setValue(composited, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                if let output = blendFilter.outputImage {
                    composited = output
                }
            }
        }

        // Render back to NSImage
        let outputExtent = ciImage.extent
        guard let outputCGImage = context.createCGImage(composited, from: outputExtent) else {
            return createWarningImage(size: image.size)
        }
        return NSImage(cgImage: outputCGImage, size: image.size)
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
