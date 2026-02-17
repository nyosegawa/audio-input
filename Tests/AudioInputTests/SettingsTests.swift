import Foundation
import XCTest

@testable import AudioInput

final class SettingsTests: XCTestCase {
    func testTranscriptionProviderDisplayName() {
        XCTAssertEqual(TranscriptionProvider.openAI.displayName, "OpenAI (gpt-4o-mini-transcribe)")
        XCTAssertEqual(TranscriptionProvider.gemini.displayName, "Gemini 2.0 Flash")
    }

    func testRecordingModeDisplayName() {
        XCTAssertEqual(RecordingMode.pushToTalk.displayName, "Push to Talk")
        XCTAssertEqual(RecordingMode.toggle.displayName, "Toggle")
    }

    func testTranscriptionProviderRawValue() {
        XCTAssertEqual(TranscriptionProvider(rawValue: "openai"), .openAI)
        XCTAssertEqual(TranscriptionProvider(rawValue: "gemini"), .gemini)
        XCTAssertNil(TranscriptionProvider(rawValue: "invalid"))
    }

    func testRecordingModeRawValue() {
        XCTAssertEqual(RecordingMode(rawValue: "push_to_talk"), .pushToTalk)
        XCTAssertEqual(RecordingMode(rawValue: "toggle"), .toggle)
        XCTAssertNil(RecordingMode(rawValue: "invalid"))
    }
}
