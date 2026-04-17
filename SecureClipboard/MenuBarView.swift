import SwiftUI

struct MenuBarView: View {
    @Bindable var state: StatusState
    let onQuit: () -> Void

    var body: some View {
        Toggle("有効", isOn: $state.isEnabled)
        Divider()

        if state.lastOriginalText != nil {
            Button("元のテキストをペースト") {
                state.pasteOriginalText()
            }
            Divider()
        }

        if state.recentDetections.isEmpty {
            Text("検出履歴なし")
                .foregroundStyle(.secondary)
        } else {
            Text("直近の検出:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.recentDetections.prefix(5)) { record in
                Text("\(record.timestamp.formatted(.dateTime.hour().minute())) — \(record.summary)")
                    .font(.caption)
            }
        }

        Divider()
        Button("終了") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}
