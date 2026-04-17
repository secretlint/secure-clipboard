import SwiftUI

struct DetectionRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: String
    let originalText: String?
    let originalImage: NSImage?
}

@Observable
final class StatusState {
    var isEnabled: Bool = true
    var isAlerted: Bool = false
    var recentDetections: [DetectionRecord] = []

    private(set) var lastOriginalText: String?
    private(set) var lastOriginalImage: NSImage?
    private var clearTimer: Timer?

    var iconName: String {
        if !isEnabled { return "lock.shield.fill" }
        return isAlerted ? "exclamationmark.shield.fill" : "lock.shield"
    }

    var iconColor: Color {
        if !isEnabled { return .secondary }
        return isAlerted ? .red : .primary
    }

    func recordDetection(summary: String, originalText: String? = nil, originalImage: NSImage? = nil) {
        let record = DetectionRecord(
            timestamp: Date(),
            summary: summary,
            originalText: originalText,
            originalImage: originalImage
        )
        recentDetections.insert(record, at: 0)
        if recentDetections.count > 5 {
            recentDetections.removeLast()
        }

        lastOriginalText = originalText
        lastOriginalImage = originalImage
        isAlerted = true

        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lastOriginalText = nil
                self?.lastOriginalImage = nil
            }
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isAlerted = false
            }
        }
    }

    /// 元のテキストを現在のアプリにキー入力としてペーストする。
    /// クリップボードを経由しないため、再マスクされない。
    func pasteOriginalText() {
        guard let text = lastOriginalText else { return }
        // 一時的にクリップボードを元テキストに差し替え、Cmd+Vをシミュレート、その後マスク済みに戻す
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // この書き換えをMonitorにスキップさせる
        onPaste?(pasteboard.changeCount)

        // Cmd+V をシミュレート
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = V
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 少し待ってからクリップボードを元に戻す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let prev = previousContents {
                pasteboard.setString(prev, forType: .string)
            }
            // ClipboardMonitorに自身の変更として通知するためonPasteを呼ぶ
            self.onPaste?(pasteboard.changeCount)
        }
    }

    /// ClipboardMonitorが自身の変更を記録するためのコールバック
    var onPaste: ((Int) -> Void)?
}
