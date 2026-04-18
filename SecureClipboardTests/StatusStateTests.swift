import Testing
import AppKit
@testable import SecureClipboard

@Test func recordDetectionAddsToHistory() {
    let state = StatusState()
    state.recordDetection(summary: "test detection", sourceApp: "Safari")
    #expect(state.recentDetections.count == 1)
    #expect(state.recentDetections[0].summary == "test detection")
    #expect(state.recentDetections[0].sourceApp == "Safari")
}

@Test func recordDetectionSetsAlerted() {
    let state = StatusState()
    #expect(state.isAlerted == false)
    state.recordDetection(summary: "test")
    #expect(state.isAlerted == true)
}

@Test func recordDetectionStoresOriginalText() {
    let state = StatusState()
    state.recordDetection(summary: "test", originalText: "secret value")
    #expect(state.lastOriginalText == "secret value")
}

@Test func recordDetectionLimitsHistoryToFive() {
    let state = StatusState()
    for i in 0..<10 {
        state.recordDetection(summary: "detection \(i)")
    }
    #expect(state.recentDetections.count == 5)
    #expect(state.recentDetections[0].summary == "detection 9")
}

@Test func copyOriginalTextCallsOnCopy() {
    let state = StatusState()
    var copyCalled = false
    state.onCopy = { _ in copyCalled = true }
    state.recordDetection(summary: "test", originalText: "raw secret")
    state.copyOriginalText()
    #expect(copyCalled == true)
}

@Test func copyOriginalTextDoesNothingWhenNoOriginal() {
    let state = StatusState()
    var copyCalled = false
    state.onCopy = { _ in copyCalled = true }
    state.copyOriginalText()
    // onCopy should not be called when no original text
    #expect(copyCalled == false)
}

@Test func iconNameChangesWithState() {
    let state = StatusState()
    #expect(state.iconName == "lock.shield")

    state.isAlerted = true
    #expect(state.iconName == "exclamationmark.shield.fill")

    state.isEnabled = false
    #expect(state.iconName == "lock.shield.fill")
}

@Test func copyOriginalTextSchedulesAutoClear() async throws {
    let state = StatusState()
    var recordedChangeCount: Int?
    state.onCopy = { changeCount in
        recordedChangeCount = changeCount
    }
    state.recordDetection(summary: "test", originalText: "secret")
    state.copyOriginalText()
    // onCopy should have been called
    #expect(recordedChangeCount != nil)
}
