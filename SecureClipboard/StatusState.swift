import SwiftUI

struct DetectionRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: String
    let sourceApp: String?
    let originalText: String?
    let originalImage: NSImage?
}

@Observable
final class StatusState {
    var isEnabled: Bool = true
    var isAlerted: Bool = false
    var recentDetections: [DetectionRecord] = []
    var autoUpdate: Bool = true
    var secretlintVersion: String?
    var updateStatus: String?
    var lastScanError: String?

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

    func recordDetection(summary: String, sourceApp: String? = nil, originalText: String? = nil, originalImage: NSImage? = nil) {
        let record = DetectionRecord(
            timestamp: Date(),
            summary: summary,
            sourceApp: sourceApp,
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
        // Use DispatchQueue to ensure timers work regardless of calling thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.lastOriginalText = nil
            self?.lastOriginalImage = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isAlerted = false
        }
    }

    /// Copy original text to clipboard (skips monitor scan), auto-clears after 10 seconds
    func copyOriginalText() {
        guard let text = lastOriginalText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Mark as concealed so clipboard managers (Alfred, etc.) don't record it
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let copyChangeCount = pasteboard.changeCount
        onCopy?(copyChangeCount)

        // Auto-clear clipboard after 90 seconds (same as 1Password default)
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            // Only clear if clipboard hasn't been changed since our copy
            if pasteboard.changeCount == copyChangeCount {
                pasteboard.clearContents()
                self?.onCopy?(pasteboard.changeCount)
            }
        }
    }

    /// Callback for ClipboardMonitor to record own clipboard changes
    var onCopy: ((Int) -> Void)?
}
