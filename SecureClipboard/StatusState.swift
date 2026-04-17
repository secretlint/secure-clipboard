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

    /// 元のテキストをクリップボードにコピーする（スキャンをスキップ）
    func copyOriginalText() {
        guard let text = lastOriginalText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onCopy?(pasteboard.changeCount)
    }

    /// ClipboardMonitorが自身の変更を記録するためのコールバック
    var onCopy: ((Int) -> Void)?
}
