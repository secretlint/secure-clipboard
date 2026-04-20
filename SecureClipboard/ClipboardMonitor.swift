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

                    let pasteboardTypes = (pasteboard.types ?? []).map { $0.rawValue }
                    let nspasteboardSource = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))

                    self.logger.debug("Clipboard changed. frontmost=\(sourceBundleId ?? "nil", privacy: .public), nspasteboard.source=\(nspasteboardSource ?? "nil", privacy: .public), types=[\(pasteboardTypes.joined(separator: ", "), privacy: .public)]")

                    // Check if the copy source should be ignored
                    let config = AppConfig.load()
                    if config.shouldSkipScan(
                        frontmostBundleId: sourceBundleId,
                        pasteboardTypes: pasteboardTypes,
                        nspasteboardSource: nspasteboardSource
                    ) {
                        Thread.sleep(forTimeInterval: 0.5)
                        continue
                    }

                    // Delay scanning if configured (default: 0 = immediate)
                    let delay = config.scanDelaySeconds ?? 0
                    if delay > 0 {
                        Thread.sleep(forTimeInterval: delay)
                        // If clipboard changed during delay, skip this scan
                        if pasteboard.changeCount != current {
                            continue
                        }
                    }

                    if let text = pasteboard.string(forType: .string), !text.isEmpty {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanText(text, sourceApp: sourceApp)
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

    private func scanText(_ text: String, sourceApp: String?) async {
        do {
            let result = try await scanner.scan(text: text)
            await MainActor.run { state.lastScanError = nil }
            switch result.action {
            case .discard(let patternName):
                logger.info("Discard pattern matched: \(patternName)")
                let newChangeCount = rewriter.rewriteText("[DISCARDED: \(patternName)]")
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(format: NSLocalizedString("detection.discarded", bundle: .module, comment: ""), patternName),
                    sourceApp: sourceApp,
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: String(format: NSLocalizedString("notification.discarded", bundle: .module, comment: ""), patternName))
            case .mask(let maskedText):
                logger.info("Secret detected in clipboard text")
                let newChangeCount = rewriter.rewriteText(maskedText)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(localized: "detection.text_masked", bundle: .module),
                    sourceApp: sourceApp,
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: String(localized: "notification.text_masked", bundle: .module))
            case .none:
                break
            }
        } catch {
            logger.error("Secret scan failed: \(error)")
            await MainActor.run {
                state.lastScanError = error.localizedDescription
            }
        }
    }

    private func scanImage(_ image: NSImage, sourceApp: String?) async {
        do {
            let result = try await imageDetector.detect(image: image)
            await MainActor.run { state.lastScanError = nil }
            guard result.hasSecrets else { return }

            switch result.scanAction {
            case .discard(let patternName):
                logger.info("Discard pattern matched in image: \(patternName)")
                let newChangeCount = rewriter.rewriteImageWithWarning(originalSize: image.size)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: String(format: NSLocalizedString("detection.discarded", bundle: .module, comment: ""), patternName),
                    sourceApp: sourceApp
                )
                sendNotification(title: "SecureClipboard", body: String(format: NSLocalizedString("notification.discarded", bundle: .module, comment: ""), patternName))
            case .mask:
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
            case .none:
                break
            }
        } catch {
            logger.error("Image secret detection failed: \(error)")
            await MainActor.run {
                state.lastScanError = error.localizedDescription
            }
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
