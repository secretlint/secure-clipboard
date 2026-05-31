import Foundation
import os

/// SecureClipboard configuration loaded from ~/.config/secure-clipboard/config.json
struct AppConfig: Codable {
    var rules: [SecretlintRule]
    var patterns: [Pattern]?
    var skipScanAppIdentifiers: [String]?
    var scanDelaySeconds: Double?
    var clearClipboardAfterSeconds: Double?

    struct SecretlintRule: Codable {
        let id: String
        let options: AnyCodable?
    }

    enum PatternAction: String, Codable {
        case mask
        case discard
    }

    struct Pattern: Codable {
        let name: String
        let pattern: String
        let action: PatternAction
        let allows: [String]?

        init(name: String, pattern: String, action: PatternAction, allows: [String]? = nil) {
            self.name = name
            self.pattern = pattern
            self.action = action
            self.allows = allows
        }
    }

    static let configPath = NSHomeDirectory() + "/.config/secure-clipboard/config.json"

    static let `default` = AppConfig(
        rules: [
            SecretlintRule(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: nil,
        skipScanAppIdentifiers: nil,
        scanDelaySeconds: nil,
        clearClipboardAfterSeconds: nil
    )

    /// Load config from disk, falling back to defaults
    static func load() -> AppConfig {
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return config
    }

    /// Convert rules + all patterns to JSON string for secretlint --secretlintrcJSON
    func secretlintrcJSON() -> String {
        // Filter out rule-pattern from user rules (managed by patterns config)
        var allRules: [[String: Any]] = rules
            .filter { $0.id != "@secretlint/secretlint-rule-pattern" }
            .map { rule in
                var dict: [String: Any] = ["id": rule.id]
                if let options = rule.options {
                    dict["options"] = options.value
                }
                return dict
            }

        // Add mask patterns only to secretlint (discard is handled by Swift)
        let maskPatterns = (patterns ?? []).filter { $0.action == .mask }
        if !maskPatterns.isEmpty {
            let patternOptions: [[String: Any]] = maskPatterns.map { p in
                var dict: [String: Any] = ["name": p.name, "pattern": p.pattern]
                if let allows = p.allows, !allows.isEmpty {
                    dict["allows"] = allows
                }
                return dict
            }
            allRules.append([
                "id": "@secretlint/secretlint-rule-pattern",
                "options": ["patterns": patternOptions]
            ])
        }

        let config: [String: Any] = ["rules": allRules]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"rules\":[{\"id\":\"@secretlint/secretlint-rule-preset-recommend\"}]}"
        }
        return json
    }

    /// Check if text matches any discard pattern (Swift-side regex)
    func matchesDiscardPattern(_ text: String) -> Pattern? {
        guard let patterns else { return nil }
        let fullRange = NSRange(text.startIndex..., in: text)
        for pattern in patterns where pattern.action == .discard {
            let (regexString, options) = parseRegex(pattern.pattern)
            guard let regex = try? NSRegularExpression(pattern: regexString, options: options) else { continue }
            let matches = regex.matches(in: text, range: fullRange)
            guard !matches.isEmpty else { continue }

            let allowRanges: [NSRange] = (pattern.allows ?? [])
                .compactMap { allowPattern -> NSRegularExpression? in
                    let (r, o) = parseRegex(allowPattern)
                    return try? NSRegularExpression(pattern: r, options: o)
                }
                .flatMap { $0.matches(in: text, range: fullRange).map { $0.range } }

            let hasNonAllowedMatch = matches.contains { m in
                !allowRanges.contains { NSIntersectionRange(m.range, $0).length > 0 }
            }
            if hasNonAllowedMatch { return pattern }
        }
        return nil
    }

    func shouldSkipScan(bundleId: String?) -> Bool {
        guard let bundleId, let ids = skipScanAppIdentifiers else { return false }
        return ids.contains(bundleId)
    }

    func shouldSkipScan(
        frontmostBundleId: String?,
        pasteboardTypes: [String],
        nspasteboardSource: String?
    ) -> Bool {
        guard let ids = skipScanAppIdentifiers else { return false }
        if let id = frontmostBundleId, ids.contains(id) { return true }
        if let source = nspasteboardSource, ids.contains(source) { return true }
        return pasteboardTypes.contains(where: { ids.contains($0) })
    }

    private func parseRegex(_ pattern: String) -> (String, NSRegularExpression.Options) {
        guard pattern.hasPrefix("/") else { return (pattern, []) }
        let trimmed = String(pattern.dropFirst())
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return (pattern, []) }

        let regexString = String(trimmed[trimmed.startIndex..<lastSlash])
        let flags = String(trimmed[trimmed.index(after: lastSlash)...])

        var options: NSRegularExpression.Options = []
        for flag in flags {
            switch flag {
            case "i": options.insert(.caseInsensitive)
            case "m": options.insert(.anchorsMatchLines)
            case "s": options.insert(.dotMatchesLineSeparators)
            default: break
            }
        }
        return (regexString, options)
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
