import AppKit
import os

final class ClipboardMonitor {
    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "ClipboardMonitor")
    private let scanner: SecretScanner
    private let imageDetector: ImageSecretDetector
    private let rewriter: ClipboardRewriter
    private let state: StatusState

    private var lastChangeCount: Int
    private var ownChangeCount: Int?
    private var isRunning = false

    init(
        scanner: SecretScanner? = nil,
        imageDetector: ImageSecretDetector? = nil,
        rewriter: ClipboardRewriter? = nil,
        state: StatusState? = nil
    ) {
        let scannerInstance = scanner ?? SecretScanner()
        self.scanner = scannerInstance
        self.imageDetector = imageDetector ?? ImageSecretDetector(scanner: scannerInstance)
        self.rewriter = rewriter ?? ClipboardRewriter()
        self.state = state ?? StatusState()
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func hasClipboardChanged(since changeCount: Int) -> Bool {
        let currentChangeCount = NSPasteboard.general.changeCount
        if currentChangeCount == changeCount { return false }
        if let own = ownChangeCount, currentChangeCount == own { return false }
        return true
    }

    func recordOwnChange(changeCount: Int) {
        ownChangeCount = changeCount
    }

    func start() {
        isRunning = true
        Thread.detachNewThread { [self] in
            while self.isRunning {
                guard self.state.isEnabled else {
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                let pasteboard = NSPasteboard.general
                let current = pasteboard.changeCount
                if current != self.lastChangeCount, self.ownChangeCount != current {
                    self.lastChangeCount = current
                    if let text = pasteboard.string(forType: .string), !text.isEmpty {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanText(text)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                              let image = NSImage(data: imageData) {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanImage(image)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    func stop() {
        isRunning = false
    }

    private func scanText(_ text: String) async {
        do {
            let result = try await scanner.scan(text: text)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard text")
                let newChangeCount = rewriter.rewriteText(result.maskedText)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(localized: "detection.text_masked", bundle: .module),
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: String(localized: "notification.text_masked", bundle: .module))
            }
        } catch {
            logger.error("Secret scan failed: \(error)")
        }
    }

    private func scanImage(_ image: NSImage) async {
        do {
            let result = try await imageDetector.detect(image: image)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard image via OCR")
                let newChangeCount = rewriter.rewriteImageWithRedaction(original: image, secretBounds: result.secretBounds)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(localized: "detection.image_detected", bundle: .module),
                    originalImage: image
                )
                sendNotification(title: "SecureClipboard", body: String(localized: "notification.image_detected", bundle: .module))
            }
        } catch {
            logger.error("Image secret detection failed: \(error)")
        }
    }

    private func sendNotification(title: String, body: String) {
        // NSUserNotificationCenter is deprecated but works without a Bundle Identifier,
        // unlike UNUserNotificationCenter which crashes in SPM command-line builds.
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
