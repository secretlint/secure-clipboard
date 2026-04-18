import SwiftUI

final class AppState {
    static let shared = AppState()
    let statusState = StatusState()
    var monitor: ClipboardMonitor?
    var ipcServer: IPCServer?

    private init() {
        let scanner = SecretScanner()
        let rewriter = ClipboardRewriter()
        let m = ClipboardMonitor(scanner: scanner, rewriter: rewriter, state: statusState)
        statusState.onCopy = { changeCount in
            m.recordOwnChange(changeCount: changeCount)
        }
        monitor = m
        m.start()

        // Start IPC server for CLI tools
        let ipc = IPCServer(scanner: scanner, rewriter: rewriter, state: statusState)
        ipc.start()
        ipcServer = ipc

        // Check for secretlint updates on launch
        let state = statusState
        let updater = SecretlintUpdater()
        Task {
            let currentVersion = await updater.currentVersion()
            await MainActor.run { state.secretlintVersion = currentVersion }
            guard state.autoUpdate else {
                await MainActor.run { state.updateStatus = String(localized: "update.disabled", bundle: .module) }
                return
            }
            let result = await updater.updateIfNeeded()
            await MainActor.run {
                switch result {
                case .upToDate(let version):
                    let fmt = NSLocalizedString("update.up_to_date", bundle: .module, comment: "")
                    state.updateStatus = String(format: fmt, version)
                case .updated(let from, let to):
                    let fmt = NSLocalizedString("update.updated", bundle: .module, comment: "")
                    state.updateStatus = String(format: fmt, from, to)
                    state.secretlintVersion = to
                case .skipped(let reason):
                    state.updateStatus = reason
                case .failed(let error):
                    let fmt = NSLocalizedString("update.failed", bundle: .module, comment: "")
                    state.updateStatus = String(format: fmt, error)
                }
            }
        }
    }
}

@main
struct SecureClipboardApp: App {
    private let appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: appState.statusState) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: appState.statusState.iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.statusState.isAlerted ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)
    }
}
