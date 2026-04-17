import Foundation
import os

actor SecretlintUpdater {
    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "Updater")
    private let binaryPath: String

    init(binaryPath: String? = nil) {
        if let path = binaryPath {
            self.binaryPath = path
        } else if let url = Bundle.module.url(forResource: "secretlint", withExtension: nil, subdirectory: "Resources") {
            self.binaryPath = url.path
        } else {
            self.binaryPath = "secretlint"
        }
    }

    /// Get the currently installed secretlint version
    func currentVersion() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--version"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return version
        } catch {
            logger.error("Failed to get current version: \(error)")
            return nil
        }
    }

    /// Fetch latest release version from GitHub API
    func latestVersion() async throws -> (version: String, downloadURL: String, checksumURL: String) {
        let url = URL(string: "https://api.github.com/repos/secretlint/secretlint/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let tagName = json?["tag_name"] as? String else {
            throw UpdateError.invalidResponse
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        let arch = ProcessInfo.processInfo.machineArchitecture
        let platform: String
        switch arch {
        case "arm64":
            platform = "darwin-arm64"
        case "x86_64":
            platform = "darwin-x64"
        default:
            throw UpdateError.unsupportedArchitecture(arch)
        }

        let binaryName = "secretlint-\(version)-\(platform)"
        let downloadURL = "https://github.com/secretlint/secretlint/releases/download/v\(version)/\(binaryName)"
        let checksumURL = "https://github.com/secretlint/secretlint/releases/download/v\(version)/secretlint-\(version)-sha256sum.txt"

        return (version, downloadURL, checksumURL)
    }

    /// Download and replace binary if a newer version is available
    func updateIfNeeded() async -> UpdateResult {
        do {
            guard let current = await currentVersion() else {
                logger.warning("Could not determine current version")
                return .skipped(reason: String(localized: "update.version_failed", bundle: .module))
            }

            let latest = try await latestVersion()

            if current == latest.version {
                logger.info("Already up to date: \(current)")
                return .upToDate(version: current)
            }

            logger.info("Update available: \(current) → \(latest.version)")

            // Download binary and checksum
            let (binaryData, _) = try await URLSession.shared.data(from: URL(string: latest.downloadURL)!)
            let (checksumData, _) = try await URLSession.shared.data(from: URL(string: latest.checksumURL)!)

            // Verify checksum
            let checksumText = String(data: checksumData, encoding: .utf8) ?? ""
            let binaryName = URL(string: latest.downloadURL)!.lastPathComponent
            guard let expectedHash = extractChecksum(from: checksumText, for: binaryName) else {
                throw UpdateError.checksumNotFound
            }
            let actualHash = sha256(data: binaryData)
            guard expectedHash == actualHash else {
                throw UpdateError.checksumMismatch(expected: expectedHash, actual: actualHash)
            }

            // Replace binary
            let tempPath = binaryPath + ".new"
            try binaryData.write(to: URL(fileURLWithPath: tempPath))

            // Set executable permission
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: tempPath)

            // Atomic swap
            let backupPath = binaryPath + ".bak"
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.moveItem(atPath: binaryPath, toPath: backupPath)
            try FileManager.default.moveItem(atPath: tempPath, toPath: binaryPath)
            try? FileManager.default.removeItem(atPath: backupPath)

            logger.info("Updated secretlint: \(current) → \(latest.version)")
            return .updated(from: current, to: latest.version)

        } catch {
            logger.error("Update check failed: \(error)")
            return .failed(error: error.localizedDescription)
        }
    }

    private func extractChecksum(from text: String, for filename: String) -> String? {
        for line in text.split(separator: "\n") {
            if line.contains(filename) {
                return String(line.split(separator: " ").first ?? "")
            }
        }
        return nil
    }

    private func sha256(data: Data) -> String {
        // Use shasum process instead of CommonCrypto
        let tempFile = NSTemporaryDirectory() + UUID().uuidString
        try? data.write(to: URL(fileURLWithPath: tempFile))
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", tempFile]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return String(output.split(separator: " ").first ?? "")
    }
}

enum UpdateResult {
    case upToDate(version: String)
    case updated(from: String, to: String)
    case skipped(reason: String)
    case failed(error: String)
}

enum UpdateError: Error {
    case invalidResponse
    case unsupportedArchitecture(String)
    case checksumNotFound
    case checksumMismatch(expected: String, actual: String)
}

extension ProcessInfo {
    /// Get machine architecture
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
