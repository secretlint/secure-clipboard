import Testing
@testable import SecureClipboard

@Test func scanResultNoneHasNoSecrets() {
    let result = ScanResult(action: .none, originalText: "hello")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "hello")
}

@Test func scanResultMaskHasSecrets() {
    let result = ScanResult(action: .mask(maskedText: "h***o"), originalText: "hello")
    #expect(result.hasSecrets == true)
    #expect(result.maskedText == "h***o")
}

@Test func scanResultDiscardHasSecrets() {
    let result = ScanResult(action: .discard(patternName: "ng-word"), originalText: "secret content")
    #expect(result.hasSecrets == true)
    #expect(result.maskedText == "secret content") // maskedText returns original for discard
}
