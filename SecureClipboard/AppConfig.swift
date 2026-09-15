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
        case replace
    }

    struct Pattern: Codable {
        let name: String
        let pattern: String
        let action: PatternAction
        let allows: [String]?
        let replacement: String?

        init(name: String, pattern: String, action: PatternAction, allows: [String]? = nil, replacement: String? = nil) {
            self.name = name
            self.pattern = pattern
            self.action = action
            self.allows = allows
            self.replacement = replacement
        }

        /// `replace` without a usable replacement fails closed by behaving as `mask`.
        var effectiveAction: PatternAction {
            if action == .replace, (replacement ?? "").isEmpty { return .mask }
            return action
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

        // Add mask patterns only to secretlint (discard/replace are handled by Swift).
        // `replace` without a non-empty replacement falls back to mask (fail closed).
        let maskPatterns = (patterns ?? []).filter { $0.effectiveAction == .mask }
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
        for pattern in patterns where pattern.action == .discard {
            if !nonAllowedMatchRanges(pattern, in: text).isEmpty { return pattern }
        }
        return nil
    }

    /// Replace every non-allowed match of each `replace` pattern with its literal
    /// replacement string. Replacement is literal — no regex template expansion.
    func applyingReplacePatterns(to text: String) -> String {
        let replacePatterns = (patterns ?? []).filter { $0.effectiveAction == .replace }
        guard !replacePatterns.isEmpty else { return text }

        // Collect all ranges against the original text, in config order.
        var chosen: [(range: NSRange, replacement: String)] = []
        for pattern in replacePatterns {
            guard let replacement = pattern.replacement, !replacement.isEmpty else { continue }
            for range in nonAllowedMatchRanges(pattern, in: text) where range.length > 0 {
                if !chosen.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                    chosen.append((range, replacement))
                }
            }
        }
        guard !chosen.isEmpty else { return text }

        // Mutate in UTF-16/NSRange space, highest offset first so earlier offsets stay valid.
        let mutable = NSMutableString(string: text)
        for item in chosen.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: item.range, with: item.replacement)
        }
        return mutable as String
    }

    /// Match ranges of `pattern` in `text` that do not overlap any `allows` regex.
    private func nonAllowedMatchRanges(_ pattern: Pattern, in text: String) -> [NSRange] {
        let fullRange = NSRange(text.startIndex..., in: text)
        let (regexString, options) = parseRegex(pattern.pattern)
        guard let regex = try? NSRegularExpression(pattern: regexString, options: options) else { return [] }
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return [] }

        let allowRanges: [NSRange] = (pattern.allows ?? [])
            .compactMap { allowPattern -> NSRegularExpression? in
                let (r, o) = parseRegex(allowPattern)
                return try? NSRegularExpression(pattern: r, options: o)
            }
            .flatMap { $0.matches(in: text, range: fullRange).map { $0.range } }

        return matches.map(\.range).filter { range in
            !allowRanges.contains { NSIntersectionRange(range, $0).length > 0 }
        }
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
