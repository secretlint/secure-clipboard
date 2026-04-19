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

@Test func copyOriginalTextDoesNothingWhenNoOriginal() {
    let state = StatusState()
    var copyCalled = false
    state.onCopy = { _ in copyCalled = true }
    state.copyOriginalText()
    #expect(copyCalled == false)
}

@Test func copyOriginalImageDoesNothingWhenNoOriginal() {
    let state = StatusState()
    var copyCalled = false
    state.onCopy = { _ in copyCalled = true }
    state.copyOriginalImage()
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

// Tests that write to NSPasteboard.general must run serially
// to avoid interference from parallel tests.
@Suite(.serialized)
struct StatusStatePasteboardTests {
    @Test func copyOriginalTextCallsOnCopy() {
        let state = StatusState()
        var copyCalled = false
        state.onCopy = { _ in copyCalled = true }
        state.recordDetection(summary: "test", originalText: "raw secret")
        state.copyOriginalText()
        #expect(copyCalled == true)
    }

    @Test func copyOriginalImageCallsOnCopy() {
        let state = StatusState()
        var copyCalled = false
        state.onCopy = { _ in copyCalled = true }
        let image = NSImage(size: NSSize(width: 10, height: 10))
        state.recordDetection(summary: "test", originalImage: image)
        state.copyOriginalImage()
        #expect(copyCalled == true)
    }

    @Test func copyOriginalImageWritesToPasteboard() {
        let state = StatusState()
        let image = NSImage(size: NSSize(width: 10, height: 10))
        state.onCopy = { _ in }
        state.recordDetection(summary: "test", originalImage: image)
        state.copyOriginalImage()
        let pasteboard = NSPasteboard.general
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) != nil)
    }

    @Test func copyOriginalTextSchedulesAutoClear() async throws {
        let state = StatusState()
        var recordedChangeCount: Int?
        state.onCopy = { changeCount in
            recordedChangeCount = changeCount
        }
        state.recordDetection(summary: "test", originalText: "secret")
        state.copyOriginalText()
        #expect(recordedChangeCount != nil)
    }
}
