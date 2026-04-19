import SwiftUI

struct MenuBarView: View {
    @Bindable var state: StatusState
    let onQuit: () -> Void

    private let repoURL = URL(string: "https://github.com/secretlint/secure-clipboard")!
    private let defaultConfig = """
    {
        "rules": [
            {
                "id": "@secretlint/secretlint-rule-preset-recommend"
            }
        ],
        "patterns": [],
        "skipScanAppIdentifiers": []
    }
    """

    var body: some View {
        Toggle(String(localized: "menu.enabled", bundle: .module), isOn: $state.isEnabled)
        Toggle(String(localized: "menu.auto_update", bundle: .module), isOn: $state.autoUpdate)
        Button(String(localized: "menu.open_config", bundle: .module)) {
            openConfig()
        }
        Button(String(localized: "menu.install_cli", bundle: .module)) {
            installCLITools()
        }
        Divider()

        if state.lastOriginalText != nil {
            Button(String(localized: "menu.copy_original", bundle: .module)) {
                state.copyOriginalText()
            }
            Divider()
        }

        if state.lastOriginalImage != nil {
            Button(String(localized: "menu.copy_original_image", bundle: .module)) {
                state.copyOriginalImage()
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
                let appLabel = record.sourceApp.map { " (\($0))" } ?? ""
                Text("\(record.timestamp.formatted(.dateTime.hour().minute())) — \(record.summary)\(appLabel)")
                    .font(.caption)
            }
        }

        if let scanError = state.lastScanError {
            Divider()
            Text("⚠ Scan error: \(scanError)")
                .font(.caption)
                .foregroundStyle(.red)
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

    private func installCLITools() {
        let binDir = "/usr/local/bin"
        guard let appPath = Bundle.main.bundlePath as String? else { return }
        let macosDir = "\(appPath)/Contents/MacOS"
        let tools = ["secure-pbpaste", "secure-pbcopy"]

        let commands = tools.map { tool in
            "ln -sf '\(macosDir)/\(tool)' '\(binDir)/\(tool)'"
        }.joined(separator: " && ")

        let script = "do shell script \"mkdir -p \(binDir) && \(commands)\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                let alert = NSAlert()
                alert.messageText = "Install Failed"
                alert.informativeText = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                alert.runModal()
            } else {
                let alert = NSAlert()
                alert.messageText = "CLI Tools Installed"
                alert.informativeText = "secure-pbpaste and secure-pbcopy are now available in \(binDir)"
                alert.runModal()
            }
        }
    }

    private func openConfig() {
        let configPath = AppConfig.configPath
        let url = URL(fileURLWithPath: configPath)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: configPath) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? defaultConfig.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
