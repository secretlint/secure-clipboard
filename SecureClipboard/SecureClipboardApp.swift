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
    }
}
