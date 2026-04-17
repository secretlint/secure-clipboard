import SwiftUI

@main
struct SecureClipboardApp: App {
    @State private var state = StatusState()
    @State private var monitor: ClipboardMonitor?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: state.iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(state.isAlerted ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        let statusState = StatusState()
        _state = State(initialValue: statusState)
        let m = ClipboardMonitor(state: statusState)
        statusState.onCopy = { changeCount in
            m.recordOwnChange(changeCount: changeCount)
        }
        _monitor = State(initialValue: m)
        m.start()

        // Check for secretlint updates on launch
        let updater = SecretlintUpdater()
        Task {
            let currentVersion = await updater.currentVersion()
            await MainActor.run {
                statusState.secretlintVersion = currentVersion
            }
            guard statusState.autoUpdate else {
                await MainActor.run {
                    statusState.updateStatus = "Auto update disabled"
                }
                return
            }
            let result = await updater.updateIfNeeded()
            await MainActor.run {
                switch result {
                case .upToDate(let version):
                    statusState.updateStatus = "Up to date (v\(version))"
                case .updated(let from, let to):
                    statusState.updateStatus = "Updated (v\(from) → v\(to))"
                    statusState.secretlintVersion = to
                case .skipped(let reason):
                    statusState.updateStatus = reason
                case .failed(let error):
                    statusState.updateStatus = "Update check failed: \(error)"
                }
            }
        }
    }
}
