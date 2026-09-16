import Foundation
import Testing
@testable import SecureClipboard

@Test func skipScanAppIdentifiers() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.1password.1password"]
    )
    #expect(config.shouldSkipScan(bundleId: "com.1password.1password") == true)
    #expect(config.shouldSkipScan(bundleId: "com.apple.Safari") == false)
    #expect(config.shouldSkipScan(bundleId: nil) == false)
}

@Test func skipScanWithNoConfig() {
    let config = AppConfig(rules: [], patterns: nil, skipScanAppIdentifiers: nil)
    #expect(config.shouldSkipScan(bundleId: "com.apple.Safari") == false)
}

@Test func secretlintrcJSONIncludesMaskPatterns() {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: [
            .init(name: "custom", pattern: "/MY_TOKEN/", action: .mask),
            .init(name: "ng", pattern: "/NG_WORD/", action: .discard)
        ]
    )
    let json = config.secretlintrcJSON()
    // Only mask patterns should be passed to secretlint
    #expect(json.contains("secretlint-rule-pattern"))
    #expect(json.contains("MY_TOKEN"))
    // Discard patterns are handled by Swift, not secretlint
    #expect(json.contains("NG_WORD") == false)
}

@Test func secretlintrcJSONExcludesDiscardPatterns() {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: [
            .init(name: "confidential", pattern: "/CONFIDENTIAL/i", action: .discard)
        ]
    )
    let json = config.secretlintrcJSON()
    // Discard-only patterns should not be in secretlintrc
    #expect(json.contains("CONFIDENTIAL") == false)
    #expect(json.contains("secretlint-rule-pattern") == false)
}

@Test func secretlintrcJSONWithNoPatterns() {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: nil
    )
    let json = config.secretlintrcJSON()
    #expect(json.contains("secretlint-rule-preset-recommend"))
    // Should not contain rule-pattern when no custom patterns
    #expect(json.contains("secretlint-rule-pattern") == false)
}

@Test func defaultConfigHasPresetRecommend() {
    let config = AppConfig.default
    let json = config.secretlintrcJSON()
    #expect(json.contains("secretlint-rule-preset-recommend"))
}

@Test func rulePatternInRulesIsIgnored() {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil),
            .init(id: "@secretlint/secretlint-rule-pattern", options: nil)
        ],
        patterns: [
            .init(name: "custom", pattern: "/TOKEN/", action: .mask)
        ]
    )
    let json = config.secretlintrcJSON()
    // rule-pattern should appear only once (from patterns, not from rules)
    let count = json.components(separatedBy: "secretlint-rule-pattern").count - 1
    #expect(count == 1)
}

@Test func discardPatternNamesExtracted() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "mask-only", pattern: "/SECRET/", action: .mask),
            .init(name: "ng-word", pattern: "/CONFIDENTIAL/", action: .discard),
            .init(name: "another-ng", pattern: "/TOP_SECRET/", action: .discard)
        ]
    )
    let discardNames = Set(
        (config.patterns ?? [])
            .filter { $0.action == .discard }
            .map(\.name)
    )
    #expect(discardNames == Set(["ng-word", "another-ng"]))
    #expect(discardNames.contains("mask-only") == false)
}

@Test func matchesDiscardPatternSimple() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "ng", pattern: "/CONFIDENTIAL/", action: .discard)
        ]
    )
    #expect(config.matchesDiscardPattern("this is CONFIDENTIAL info")?.name == "ng")
    #expect(config.matchesDiscardPattern("this is public info") == nil)
}

@Test func matchesDiscardPatternCaseInsensitive() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "ng", pattern: "/confidential/i", action: .discard)
        ]
    )
    #expect(config.matchesDiscardPattern("this is CONFIDENTIAL info")?.name == "ng")
}

@Test func scanDelaySecondsDefaultIsNil() {
    let config = AppConfig.default
    #expect(config.scanDelaySeconds == nil)
}

@Test func scanDelaySecondsParsesFromJSON() throws {
    let json = """
    {"rules":[],"scanDelaySeconds":15}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.scanDelaySeconds == 15)
}

@Test func scanDelaySecondsOptionalInJSON() throws {
    let json = """
    {"rules":[]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.scanDelaySeconds == nil)
}

@Test func matchesDiscardPatternIgnoresMask() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "mask-only", pattern: "/SECRET/", action: .mask)
        ]
    )
    #expect(config.matchesDiscardPattern("this has SECRET in it") == nil)
}

@Test func shouldSkipScanMatchesFrontmost() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.1password.1password"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.1password.1password",
        pasteboardTypes: [],
        nspasteboardSource: nil
    ) == true)
}

@Test func shouldSkipScanMatchesPasteboardType() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.runningwithcrayons.alfred.clipping"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Terminal",
        pasteboardTypes: ["public.utf8-plain-text", "com.runningwithcrayons.alfred.clipping"],
        nspasteboardSource: nil
    ) == true)
}

@Test func shouldSkipScanMatchesNspasteboardSource() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.example.SourceApp"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: [],
        nspasteboardSource: "com.example.SourceApp"
    ) == true)
}

@Test func shouldSkipScanNoMatchReturnsFalse() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.1password.1password"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: ["public.utf8-plain-text"],
        nspasteboardSource: nil
    ) == false)
}

@Test func shouldSkipScanNilIdentifiersReturnsFalse() {
    let config = AppConfig(rules: [], patterns: nil, skipScanAppIdentifiers: nil)
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: ["public.utf8-plain-text"],
        nspasteboardSource: "com.example.App"
    ) == false)
}

@Test func secretlintrcJSONIncludesPatternAllows() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "aaa-token",
                pattern: "/aaa/",
                action: .mask,
                allows: ["/https?:\\/\\/[^\\s]*aaa/"]
            )
        ]
    )
    let json = config.secretlintrcJSON()
    #expect(json.contains("aaa-token"))
    #expect(json.contains("\"allows\""))
    #expect(json.contains("https"))
}

@Test func secretlintrcJSONOmitsAllowsWhenNil() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "x", pattern: "/TOKEN/", action: .mask)
        ]
    )
    let json = config.secretlintrcJSON()
    #expect(json.contains("\"allows\"") == false)
}

@Test func matchesDiscardPatternRespectsAllows() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "ng",
                pattern: "/aaa/",
                action: .discard,
                allows: ["/https?:\\/\\/[^\\s]*aaa/"]
            )
        ]
    )
    // 裸のaaaはdiscard対象
    #expect(config.matchesDiscardPattern("plain aaa here")?.name == "ng")
    // URL中のaaaはallowされる
    #expect(config.matchesDiscardPattern("see https://example.com/aaa for details") == nil)
}

@Test func matchesDiscardPatternAllowsOnlyOverlapping() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "ng",
                pattern: "/aaa/",
                action: .discard,
                allows: ["/https?:\\/\\/[^\\s]*aaa/"]
            )
        ]
    )
    // URL中のaaaは許可されても、別の場所の裸のaaaはdiscard対象
    #expect(config.matchesDiscardPattern("url https://example.com/aaa and plain aaa")?.name == "ng")
}

@Test func clearClipboardAfterSecondsDefaultIsNil() {
    let config = AppConfig.default
    #expect(config.clearClipboardAfterSeconds == nil)
}

@Test func clearClipboardAfterSecondsParsesFromJSON() throws {
    let json = """
    {"rules":[],"clearClipboardAfterSeconds":60}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.clearClipboardAfterSeconds == 60)
}

@Test func clearClipboardAfterSecondsOptionalInJSON() throws {
    let json = """
    {"rules":[]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.clearClipboardAfterSeconds == nil)
}

// MARK: - replace action

@Test func replacePatternReplacesMatchOnly() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "token-value",
                pattern: "/(?<=PROXMOX_TOKEN_SECRET=)[0-9a-f]{32}/",
                action: .replace,
                replacement: "[REDACTED]"
            )
        ]
    )
    let input = "PROXMOX_TOKEN_SECRET=0123456789abcdef0123456789abcdef"
    #expect(config.applyingReplacePatterns(to: input) == "PROXMOX_TOKEN_SECRET=[REDACTED]")
}

@Test func replacePatternHandlesUnicodeAroundMultipleMatches() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "hex-token", pattern: "/[0-9a-f]{16,}/", action: .replace, replacement: "[REDACTED]")
        ]
    )
    let input = "PREFIX_😀 API_TOKEN=0123456789abcdef MIDDLE_äöü NOTIFY_TOKEN=abcdef1234567890 SUFFIX"
    let expected = "PREFIX_😀 API_TOKEN=[REDACTED] MIDDLE_äöü NOTIFY_TOKEN=[REDACTED] SUFFIX"
    #expect(config.applyingReplacePatterns(to: input) == expected)
}

@Test func replacePatternHandlesRepeatedSamePattern() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "hex-token", pattern: "/[0-9a-f]{16,}/", action: .replace, replacement: "[REDACTED]")
        ]
    )
    let input = "API_TOKEN=0123456789abcdef\nAPI_TOKEN=abcdef1234567890"
    let expected = "API_TOKEN=[REDACTED]\nAPI_TOKEN=[REDACTED]"
    #expect(config.applyingReplacePatterns(to: input) == expected)
}

@Test func replacePatternReplacementIsLiteral() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "token", pattern: "/SECRET/", action: .replace, replacement: "$1\\foo[REDACTED]")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "value=SECRET") == "value=$1\\foo[REDACTED]")
}

@Test func replacePatternReplacementLiteralDollarAndBackslash() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "token", pattern: "/SECRET/", action: .replace, replacement: "$$\\1")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "aSECRETb") == "a$$\\1b")
}

@Test func replacePatternUnicodeReplacement() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "token", pattern: "/SECRET/", action: .replace, replacement: "🔒秘")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "a SECRET b") == "a 🔒秘 b")
}

@Test func replacePatternRespectsAllows() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(
                name: "aaa-token",
                pattern: "/aaa/",
                action: .replace,
                allows: ["/https?:\\/\\/[^\\s]*aaa/"],
                replacement: "[REDACTED]"
            )
        ]
    )
    #expect(
        config.applyingReplacePatterns(to: "url https://example.com/aaa and plain aaa")
            == "url https://example.com/aaa and plain [REDACTED]"
    )
}

@Test func replacePatternOverlapFirstConfigWins() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "first", pattern: "/abc/", action: .replace, replacement: "[FIRST]"),
            .init(name: "second", pattern: "/bcd/", action: .replace, replacement: "[SECOND]")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "abcd") == "[FIRST]d")
}

@Test func replacePatternInvalidRegexIsSkipped() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "bad", pattern: "/([unclosed/", action: .replace, replacement: "[REDACTED]")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "unchanged text") == "unchanged text")
}

@Test func replacePatternZeroLengthMatchIsIgnored() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "empty", pattern: "/x*/", action: .replace, replacement: "[R]")
        ]
    )
    #expect(config.applyingReplacePatterns(to: "abc") == "abc")
}

@Test func secretlintrcJSONExcludesReplacePatterns() {
    let config = AppConfig(
        rules: [
            .init(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: [
            .init(name: "token", pattern: "/TOKEN/", action: .replace, replacement: "[REDACTED]")
        ]
    )
    let json = config.secretlintrcJSON()
    #expect(json.contains("secretlint-rule-pattern") == false)
    #expect(json.contains("TOKEN") == false)
}

@Test func replacePatternMissingReplacementFallsBackToMask() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "token", pattern: "/TOKEN/", action: .replace, replacement: nil)
        ]
    )
    let json = config.secretlintrcJSON()
    #expect(json.contains("secretlint-rule-pattern"))
    #expect(json.contains("TOKEN"))
    #expect(config.applyingReplacePatterns(to: "a TOKEN b") == "a TOKEN b")
}

@Test func replacePatternEmptyReplacementFallsBackToMask() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "token", pattern: "/TOKEN/", action: .replace, replacement: "")
        ]
    )
    #expect(config.secretlintrcJSON().contains("TOKEN"))
    #expect(config.applyingReplacePatterns(to: "a TOKEN b") == "a TOKEN b")
}

@Test func patternDecodingWithoutReplacementIsNil() throws {
    let json = """
    {"rules":[],"patterns":[{"name":"m","pattern":"/X/","action":"mask"}]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.patterns?.first?.replacement == nil)
}

@Test func patternDecodingWithReplace() throws {
    let json = """
    {"rules":[],"patterns":[{"name":"r","pattern":"/X/","action":"replace","replacement":"[REDACTED]"}]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.patterns?.first?.action == .replace)
    #expect(config.patterns?.first?.replacement == "[REDACTED]")
}
