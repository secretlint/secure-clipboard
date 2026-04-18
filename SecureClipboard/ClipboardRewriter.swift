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

    /// Pixellate then blur secret regions for natural-looking redaction
    private func redactRegions(image: NSImage, regions: [CGRect]) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return createWarningImage(size: image.size)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let padding: CGFloat = 4

        // Crystallize (irregular polygonal cells) + blur for natural-looking redaction
        guard let crystallizeFilter = CIFilter(name: "CICrystallize"),
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return createWarningImage(size: image.size)
        }
        crystallizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        crystallizeFilter.setValue(15.0, forKey: kCIInputRadiusKey)
        guard let crystallized = crystallizeFilter.outputImage else {
            return createWarningImage(size: image.size)
        }
        blurFilter.setValue(crystallized, forKey: kCIInputImageKey)
        blurFilter.setValue(6.0, forKey: kCIInputRadiusKey)
        guard let redactedVersion = blurFilter.outputImage else {
            return createWarningImage(size: image.size)
        }

        // Composite: use redacted version only in secret regions
        // Use different crystallize center per region to prevent pattern-based recovery
        var composited = ciImage
        for region in regions {
            let pixelRect = CGRect(
                x: (region.origin.x - padding) * scaleX,
                y: (region.origin.y - padding) * scaleY,
                width: (region.size.width + padding * 2) * scaleX,
                height: (region.size.height + padding * 2) * scaleY
            )

            // Randomize crystallize center per region
            let randomCenter = CIVector(
                x: CGFloat.random(in: 0...CGFloat(cgImage.width)),
                y: CGFloat.random(in: 0...CGFloat(cgImage.height))
            )
            crystallizeFilter.setValue(randomCenter, forKey: kCIInputCenterKey)
            guard let regionCrystallized = crystallizeFilter.outputImage else { continue }
            blurFilter.setValue(regionCrystallized, forKey: kCIInputImageKey)
            guard let regionRedacted = blurFilter.outputImage else { continue }

            let maskImage = CIImage(color: .white).cropped(to: pixelRect)
            if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                blendFilter.setValue(regionRedacted, forKey: kCIInputImageKey)
                blendFilter.setValue(composited, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                if let output = blendFilter.outputImage {
                    composited = output
                }
            }
        }

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
