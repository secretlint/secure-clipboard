import Foundation

/// CLI tool that communicates with the running SecureClipboard app via Unix Domain Socket
@main
struct SecurePBMain {
    static let socketPath = "/tmp/secure-clipboard.sock"

    static func main() {
        let command = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

        switch command {
        case "secure-pbcopy":
            copy()
        case "secure-pbpaste":
            paste()
        default:
            paste()
        }
    }

    static func copy() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return
        }
        let response = sendToApp("COPY\n\(text)")
        if response == nil {
            fputs("Error: SecureClipboard app could not be started\n", stderr)
            exit(1)
        }
    }

    static func paste() {
        let response = sendToApp("PASTE\n")
        if let response {
            print(response, terminator: "")
        } else {
            fputs("Error: SecureClipboard app could not be started\n", stderr)
            exit(1)
        }
    }

    static func sendToApp(_ message: String) -> String? {
        // Try to connect, if app not running launch it and retry
        if let response = connectAndSend(message) {
            return response
        }

        // Launch app and retry
        let appPath = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent() // MacOS/
            .deletingLastPathComponent() // Contents/
            .deletingLastPathComponent() // .app/
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", appPath.path]
        try? task.run()
        task.waitUntilExit()

        // Wait for socket to become available (max 5 seconds)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            if let response = connectAndSend(message) {
                return response
            }
        }
        return nil
    }

    static func connectAndSend(_ message: String) -> String? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    strcpy(dest, ptr)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        let msgData = Array(message.utf8)
        write(sock, msgData, msgData.count)
        shutdown(sock, SHUT_WR)

        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        let bytesRead = read(sock, &buffer, buffer.count)
        guard bytesRead > 0 else { return "" }
        return String(bytes: buffer[0..<bytesRead], encoding: .utf8)
    }
}
