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

    /// Fill secret regions with background color, then crystallize + blur for natural redaction
    private func redactRegions(image: NSImage, regions: [CGRect]) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return createWarningImage(size: image.size)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let padding: CGFloat = 4

        // Step 1: Paint over text with sampled background color per region
        var painted = ciImage
        for region in regions {
            let pixelRect = CGRect(
                x: (region.origin.x - padding) * scaleX,
                y: (region.origin.y - padding) * scaleY,
                width: (region.size.width + padding * 2) * scaleX,
                height: (region.size.height + padding * 2) * scaleY
            )
            // Sample background color from the edge of the region
            let bgColor = sampleEdgeColor(image: cgImage, rect: pixelRect)
            let colorFill = CIImage(color: bgColor).cropped(to: pixelRect)
            let maskImage = CIImage(color: .white).cropped(to: pixelRect)
            if let blendFilter = CIFilter(name: "CIBlendWithMask") {
                blendFilter.setValue(colorFill, forKey: kCIInputImageKey)
                blendFilter.setValue(painted, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                if let output = blendFilter.outputImage {
                    painted = output
                }
            }
        }

        // Step 2: Crystallize + blur the painted image, then composite back
        guard let crystallizeFilter = CIFilter(name: "CICrystallize"),
              let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return createWarningImage(size: image.size)
        }

        var composited = ciImage
        for region in regions {
            let pixelRect = CGRect(
                x: (region.origin.x - padding) * scaleX,
                y: (region.origin.y - padding) * scaleY,
                width: (region.size.width + padding * 2) * scaleX,
                height: (region.size.height + padding * 2) * scaleY
            )

            // Randomize crystallize center per region
            crystallizeFilter.setValue(painted, forKey: kCIInputImageKey)
            crystallizeFilter.setValue(15.0, forKey: kCIInputRadiusKey)
            crystallizeFilter.setValue(CIVector(
                x: CGFloat.random(in: 0...CGFloat(cgImage.width)),
                y: CGFloat.random(in: 0...CGFloat(cgImage.height))
            ), forKey: kCIInputCenterKey)
            guard let regionCrystallized = crystallizeFilter.outputImage else { continue }

            blurFilter.setValue(regionCrystallized, forKey: kCIInputImageKey)
            blurFilter.setValue(6.0, forKey: kCIInputRadiusKey)
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

    /// Sample the average color from the edges of a rect (background, not text)
    private func sampleEdgeColor(image: CGImage, rect: CGRect) -> CIColor {
        let clampedRect = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clampedRect.isEmpty else { return CIColor.gray }

        // Sample a thin strip at the top edge of the region
        let stripHeight = max(2, Int(clampedRect.height * 0.1))
        let sampleRect = CGRect(
            x: clampedRect.origin.x,
            y: clampedRect.maxY - CGFloat(stripHeight),
            width: clampedRect.width,
            height: CGFloat(stripHeight)
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !sampleRect.isEmpty,
              let cropped = image.cropping(to: sampleRect) else { return CIColor.gray }

        // Get average color using a 1x1 resize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CIColor.gray }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return CIColor(
            red: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0
        )
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
