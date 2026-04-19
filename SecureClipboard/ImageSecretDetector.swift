import AppKit
import Vision

struct ImageDetectionResult {
    let hasSecrets: Bool
    let extractedText: String
    let scanAction: ScanAction
    /// Bounding boxes of lines containing secrets (in image coordinates, origin bottom-left)
    let secretBounds: [CGRect]
}

actor ImageSecretDetector {
    private let scanner: SecretScanner

    init(scanner: SecretScanner? = nil) {
        self.scanner = scanner ?? SecretScanner()
    }

    private struct TextObservation {
        let text: String
        let boundingBox: CGRect // normalized coordinates (0-1)
    }

    private func extractObservations(from image: NSImage) async throws -> [TextObservation] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { obs -> TextObservation? in
                        guard let candidate = obs.topCandidates(1).first else { return nil }
                        return TextObservation(text: candidate.string, boundingBox: obs.boundingBox)
                    }
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.revision = VNRecognizeTextRequestRevision3
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractText(from image: NSImage) async throws -> String {
        let observations = try await extractObservations(from: image)
        return observations.map(\.text).joined(separator: "\n")
    }

    func detect(image: NSImage) async throws -> ImageDetectionResult {
        let observations = try await extractObservations(from: image)
        if observations.isEmpty {
            return ImageDetectionResult(hasSecrets: false, extractedText: "", scanAction: .none, secretBounds: [])
        }

        let fullText = observations.map(\.text).joined(separator: "\n")
        let scanResult = try await scanner.scan(text: fullText)

        guard scanResult.hasSecrets else {
            return ImageDetectionResult(hasSecrets: false, extractedText: fullText, scanAction: .none, secretBounds: [])
        }

        // Find which lines contain masked content by comparing original vs masked line by line
        let originalLines = fullText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maskedLines = scanResult.maskedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let imageSize = image.size
        var secretBounds: [CGRect] = []

        for (i, observation) in observations.enumerated() {
            if i < originalLines.count && i < maskedLines.count && originalLines[i] != maskedLines[i] {
                // This line has secrets — convert normalized bbox to image coordinates
                let bbox = observation.boundingBox
                let rect = CGRect(
                    x: bbox.origin.x * imageSize.width,
                    y: bbox.origin.y * imageSize.height,
                    width: bbox.size.width * imageSize.width,
                    height: bbox.size.height * imageSize.height
                )
                secretBounds.append(rect)
            }
        }

        return ImageDetectionResult(
            hasSecrets: true,
            extractedText: fullText,
            scanAction: scanResult.action,
            secretBounds: secretBounds
        )
    }
}
