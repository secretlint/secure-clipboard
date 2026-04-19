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

@Test func maskDelaySecondsDefaultIsNil() {
    let config = AppConfig.default
    #expect(config.maskDelaySeconds == nil)
}

@Test func maskDelaySecondsParsesFromJSON() throws {
    let json = """
    {"rules":[],"maskDelaySeconds":15}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.maskDelaySeconds == 15)
}

@Test func maskDelaySecondsOptionalInJSON() throws {
    let json = """
    {"rules":[]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.maskDelaySeconds == nil)
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
