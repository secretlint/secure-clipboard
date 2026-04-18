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

                    // Capture source app at the moment of clipboard change
                    let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
                    let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

                    // Check if source app should be ignored
                    let config = AppConfig.load()
                    if config.shouldSkipScan(bundleId: sourceBundleId) {
                        Thread.sleep(forTimeInterval: 0.5)
                        continue
                    }

                    if let text = pasteboard.string(forType: .string), !text.isEmpty {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.processText(text, sourceApp: sourceApp, config: config)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                              let image = NSImage(data: imageData) {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanImage(image, sourceApp: sourceApp)
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

    private func processText(_ text: String, sourceApp: String?, config: AppConfig) async {
        // Check discard patterns first (entire content is discarded)
        if let matched = config.matchesDiscardPattern(text) {
            logger.info("Discard pattern matched: \(matched.name)")
            let newChangeCount = rewriter.rewriteText("[DISCARDED: \(matched.name)]")
            recordOwnChange(changeCount: newChangeCount)
            lastChangeCount = newChangeCount
            state.recordDetection(
                summary: String(localized: "detection.discarded \(matched.name)", bundle: .module),
                sourceApp: sourceApp,
                originalText: text
            )
            sendNotification(
                title: "SecureClipboard",
                body: String(localized: "notification.discarded \(matched.name)", bundle: .module)
            )
            return
        }

        // Then check secretlint rules + mask patterns
        await scanText(text, sourceApp: sourceApp)
    }

    private func scanText(_ text: String, sourceApp: String?) async {
        do {
            let result = try await scanner.scan(text: text)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard text")
                let newChangeCount = rewriter.rewriteText(result.maskedText)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(localized: "detection.text_masked", bundle: .module),
                    sourceApp: sourceApp,
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: String(localized: "notification.text_masked", bundle: .module))
            }
        } catch {
            logger.error("Secret scan failed: \(error)")
        }
    }

    private func scanImage(_ image: NSImage, sourceApp: String?) async {
        do {
            let result = try await imageDetector.detect(image: image)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard image via OCR")
                let newChangeCount = rewriter.rewriteImageWithRedaction(original: image, secretBounds: result.secretBounds)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(localized: "detection.image_detected", bundle: .module),
                    sourceApp: sourceApp,
                    originalImage: image
                )
                sendNotification(title: "SecureClipboard", body: String(localized: "notification.image_detected", bundle: .module))
            }
        } catch {
            logger.error("Image secret detection failed: \(error)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
