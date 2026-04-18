import Foundation
import AppKit
import os

/// Unix Domain Socket server for CLI tools to communicate with the app
final class IPCServer {
    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "IPCServer")
    static let socketPath = "/tmp/secure-clipboard.sock"
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let scanner: SecretScanner
    private let rewriter: ClipboardRewriter
    private let state: StatusState

    init(scanner: SecretScanner, rewriter: ClipboardRewriter, state: StatusState) {
        self.scanner = scanner
        self.rewriter = rewriter
        self.state = state
    }

    func start() {
        // Remove stale socket
        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    strcpy(dest, ptr)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            return
        }

        guard listen(serverSocket, 5) == 0 else {
            logger.error("Failed to listen on socket")
            return
        }

        isRunning = true
        Thread.detachNewThread { [self] in
            while self.isRunning {
                var clientAddr = sockaddr_un()
                var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.serverSocket, $0, &clientLen)
                    }
                }
                guard clientSocket >= 0 else { continue }

                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await self.handleClient(clientSocket)
                    semaphore.signal()
                }
                semaphore.wait()
            }
        }

        logger.info("IPC server started at \(Self.socketPath)")
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(Self.socketPath)
    }

    private func handleClient(_ clientSocket: Int32) async {
        defer { close(clientSocket) }

        // Read command (first line) and data
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024) // 1MB max
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let input = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        guard let newlineIndex = input.firstIndex(of: "\n") else { return }

        let command = String(input[input.startIndex..<newlineIndex])
        let data = String(input[input.index(after: newlineIndex)...])

        switch command {
        case "COPY":
            await handleCopy(data, clientSocket: clientSocket)
        case "PASTE":
            handlePaste(clientSocket: clientSocket)
        default:
            sendResponse(clientSocket, "ERROR:unknown command\n")
        }
    }

    private func handleCopy(_ text: String, clientSocket: Int32) async {
        do {
            let result = try await scanner.scan(text: text)
            switch result.action {
            case .discard(let patternName):
                rewriter.rewriteText("[DISCARDED: \(patternName)]")
                state.recordDetection(
                    summary: "Discarded: \(patternName)",
                    originalText: text
                )
                sendResponse(clientSocket, "DISCARDED:\(patternName)\n")
            case .mask(let maskedText):
                rewriter.rewriteText(maskedText)
                state.recordDetection(
                    summary: "Masked secrets in text",
                    originalText: text
                )
                sendResponse(clientSocket, "MASKED\n")
            case .none:
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                sendResponse(clientSocket, "OK\n")
            }
        } catch {
            // On error, copy as-is
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            sendResponse(clientSocket, "OK\n")
        }
    }

    private func handlePaste(clientSocket: Int32) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        sendResponse(clientSocket, text)
    }

    private func sendResponse(_ socket: Int32, _ response: String) {
        let data = Array(response.utf8)
        _ = write(socket, data, data.count)
    }
}
