import Testing
@testable import SecureClipboard

@Test func discardPatternMatchesSimplePattern() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "test", pattern: "/SECRET/", action: .discard)
        ]
    )
    let matched = config.matchesDiscardPattern("this has SECRET in it")
    #expect(matched?.name == "test")
}

@Test func discardPatternDoesNotMatchWhenAbsent() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "test", pattern: "/SECRET/", action: .discard)
        ]
    )
    let matched = config.matchesDiscardPattern("this is clean text")
    #expect(matched == nil)
}

@Test func discardPatternCaseInsensitiveFlag() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "test", pattern: "/secret/i", action: .discard)
        ]
    )
    let matched = config.matchesDiscardPattern("this has SECRET in it")
    #expect(matched?.name == "test")
}

@Test func discardPatternCaseSensitiveByDefault() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "test", pattern: "/secret/", action: .discard)
        ]
    )
    let matched = config.matchesDiscardPattern("this has SECRET in it")
    #expect(matched == nil)
}

@Test func discardPatternWithRegex() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "test", pattern: "/INTERNAL_\\w+/", action: .discard)
        ]
    )
    let matched = config.matchesDiscardPattern("key is INTERNAL_PROJECT_X")
    #expect(matched?.name == "test")
}

@Test func maskPatternIsNotMatchedByDiscard() {
    let config = AppConfig(
        rules: [],
        patterns: [
            .init(name: "mask-only", pattern: "/SECRET/", action: .mask)
        ]
    )
    let matched = config.matchesDiscardPattern("this has SECRET in it")
    #expect(matched == nil)
}

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
    // mask pattern should be included in secretlintrc
    #expect(json.contains("secretlint-rule-pattern"))
    #expect(json.contains("MY_TOKEN"))
    // discard pattern should NOT be in secretlintrc
    #expect(json.contains("NG_WORD") == false)
}

@Test func defaultConfigHasPresetRecommend() {
    let config = AppConfig.default
    let json = config.secretlintrcJSON()
    #expect(json.contains("secretlint-rule-preset-recommend"))
}
