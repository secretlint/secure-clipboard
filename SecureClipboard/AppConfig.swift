import Foundation
import os

/// SecureClipboard configuration loaded from ~/.config/secure-clipboard/config.json
struct AppConfig: Codable {
    var rules: [SecretlintRule]
    var rejectPatterns: [RejectPattern]?
    var ignoredApps: [String]?

    struct SecretlintRule: Codable {
        let id: String
        let options: AnyCodable?
    }

    struct RejectPattern: Codable {
        let name: String
        let pattern: String
    }

    static let configPath = NSHomeDirectory() + "/.config/secure-clipboard/config.json"

    static let `default` = AppConfig(
        rules: [
            SecretlintRule(id: "@secretlint/secretlint-rule-preset-recommend", options: nil),
            SecretlintRule(id: "@secretlint/secretlint-rule-pattern", options: nil)
        ],
        rejectPatterns: nil,
        ignoredApps: nil
    )

    /// Load config from disk, falling back to defaults
    static func load() -> AppConfig {
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return config
    }

    /// Convert rules to JSON string for secretlint --secretlintrcJSON
    func secretlintrcJSON() -> String {
        let rulesJSON: [[String: Any]] = rules.map { rule in
            var dict: [String: Any] = ["id": rule.id]
            if let options = rule.options {
                dict["options"] = options.value
            }
            return dict
        }
        let config: [String: Any] = ["rules": rulesJSON]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            return AppConfig.default.secretlintrcJSON()
        }
        return json
    }

    /// Check if text matches any reject pattern
    func matchesRejectPattern(_ text: String) -> RejectPattern? {
        guard let patterns = rejectPatterns else { return nil }
        for pattern in patterns {
            // Extract regex from /pattern/ or /pattern/flags format
            let regexString = extractRegex(from: pattern.pattern)
            if let regex = try? NSRegularExpression(pattern: regexString),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return pattern
            }
        }
        return nil
    }

    /// Check if a bundle identifier should be ignored
    func shouldIgnoreApp(bundleId: String?) -> Bool {
        guard let bundleId, let ignored = ignoredApps else { return false }
        return ignored.contains(bundleId)
    }

    private func extractRegex(from pattern: String) -> String {
        // Handle /pattern/ and /pattern/flags format
        if pattern.hasPrefix("/") {
            let trimmed = String(pattern.dropFirst())
            if let lastSlash = trimmed.lastIndex(of: "/") {
                return String(trimmed[trimmed.startIndex..<lastSlash])
            }
        }
        return pattern
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
