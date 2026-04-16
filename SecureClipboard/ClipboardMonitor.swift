import AppKit
import UserNotifications
import os

final class ClipboardMonitor {
    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "ClipboardMonitor")
    private let scanner: SecretScanner
    private let imageDetector: ImageSecretDetector
    private let rewriter: ClipboardRewriter
    private let state: StatusState

    private var lastChangeCount: Int
    private var ownChangeCount: Int?
    private var timer: Timer?

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() async {
        guard state.isEnabled else { return }
        guard hasClipboardChanged(since: lastChangeCount) else { return }

        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            await scanText(text)
            return
        }

        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            await scanImage(image)
        }
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
                    summary: "テキスト内のシークレットをマスクしました",
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: "クリップボードのシークレットをマスクしました")
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
                let newChangeCount = rewriter.rewriteImageWithWarning(originalSize: image.size)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: "画像内のシークレットを検出しました",
                    originalImage: image
                )
                sendNotification(title: "SecureClipboard", body: "クリップボードの画像にシークレットが含まれています")
            }
        } catch {
            logger.error("Image secret detection failed: \(error)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
