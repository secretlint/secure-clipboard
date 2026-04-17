import SwiftUI

struct MenuBarView: View {
    @Bindable var state: StatusState
    let onQuit: () -> Void

    private let repoURL = URL(string: "https://github.com/secretlint/secure-clipboard")!
    private let configPath = NSHomeDirectory() + "/.config/secure-clipboard/.secretlintrc.json"
    private let defaultConfig = """
    {
        "rules": [
            {
                "id": "@secretlint/secretlint-rule-preset-recommend"
            },
            {
                "id": "@secretlint/secretlint-rule-pattern"
            }
        ]
    }
    """

    var body: some View {
        Toggle(String(localized: "menu.enabled", bundle: .module), isOn: $state.isEnabled)
        Toggle(String(localized: "menu.auto_update", bundle: .module), isOn: $state.autoUpdate)
        Button(String(localized: "menu.open_secretlintrc", bundle: .module)) {
            openConfig()
        }
        Divider()

        if state.lastOriginalText != nil {
            Button(String(localized: "menu.copy_original", bundle: .module)) {
                state.copyOriginalText()
            }
            Divider()
        }

        if state.recentDetections.isEmpty {
            Text("menu.no_detections", bundle: .module)
                .foregroundStyle(.secondary)
        } else {
            Text("menu.recent", bundle: .module)
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
        Button("SecureClipboard v\(AppVersion.current)") {
            NSWorkspace.shared.open(repoURL)
        }
        .font(.caption)
        Button(String(localized: "menu.quit", bundle: .module)) {
            onQuit()
        }
        .keyboardShortcut("q")
    }

    private func openConfig() {
        let url = URL(fileURLWithPath: configPath)
        let dir = url.deletingLastPathComponent()
        // Create directory and default config if not exists
        if !FileManager.default.fileExists(atPath: configPath) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? defaultConfig.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
