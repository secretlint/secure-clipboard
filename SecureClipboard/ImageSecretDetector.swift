import AppKit
import Vision

struct ImageDetectionResult {
    let hasSecrets: Bool
    let extractedText: String
}

actor ImageSecretDetector {
    private let scanner: SecretScanner

    init(scanner: SecretScanner? = nil) {
        self.scanner = scanner ?? SecretScanner()
    }

    func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func detect(image: NSImage) async throws -> ImageDetectionResult {
        let text = try await extractText(from: image)
        if text.isEmpty {
            return ImageDetectionResult(hasSecrets: false, extractedText: "")
        }
        let scanResult = try await scanner.scan(text: text)
        return ImageDetectionResult(
            hasSecrets: scanResult.hasSecrets,
            extractedText: text
        )
    }
}
