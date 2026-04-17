import SwiftUI

struct MenuBarView: View {
    @Bindable var state: StatusState
    let onQuit: () -> Void

    private let repoURL = URL(string: "https://github.com/secretlint/secure-clipboard")!

    var body: some View {
        Text("SecureClipboard")
            .font(.headline)
        Button("GitHub") {
            NSWorkspace.shared.open(repoURL)
        }
        Divider()

        Toggle("Enabled", isOn: $state.isEnabled)
        Toggle("Auto Update", isOn: $state.autoUpdate)
        Divider()

        if state.lastOriginalText != nil {
            Button("Copy Original Text") {
                state.copyOriginalText()
            }
            Divider()
        }

        if state.recentDetections.isEmpty {
            Text("No detections")
                .foregroundStyle(.secondary)
        } else {
            Text("Recent:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.recentDetections.prefix(5)) { record in
                Text("\(record.timestamp.formatted(.dateTime.hour().minute())) — \(record.summary)")
                    .font(.caption)
            }
        }

        Divider()
        if let version = state.secretlintVersion {
            Text("secretlint v\(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let status = state.updateStatus {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Divider()
        Button("Quit") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}
