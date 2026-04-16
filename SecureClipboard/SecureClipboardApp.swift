import SwiftUI

@main
struct SecureClipboardApp: App {
    var body: some Scene {
        MenuBarExtra("SecureClipboard", systemImage: "lock.shield") {
            Text("SecureClipboard")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
