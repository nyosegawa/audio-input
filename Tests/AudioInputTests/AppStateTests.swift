import Foundation
import XCTest

@testable import AudioInput

final class AppStateTests: XCTestCase {
    @MainActor
    func testInitial() {
        let state = AppState()
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.statusText, "待機中")
    }

    @MainActor
    func testRecording() {
        let state = AppState()
        state.status = .recording
        XCTAssertTrue(state.isRecording)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertEqual(state.statusText, "録音中...")
    }

    @MainActor
    func testTranscribing() {
        let state = AppState()
        state.status = .transcribing
        XCTAssertFalse(state.isRecording)
        XCTAssertTrue(state.isTranscribing)
        XCTAssertEqual(state.statusText, "文字起こし中...")
    }

    @MainActor
    func testError() {
        let state = AppState()
        state.status = .error("テストエラー")
        XCTAssertFalse(state.isRecording)
        XCTAssertEqual(state.statusText, "エラー: テストエラー")
    }

    @MainActor
    func testAddRecord() {
        let state = AppState()
        let record = TranscriptionRecord(
            text: "テスト文字列",
            date: Date(),
            duration: 2.5,
            provider: .openAI
        )
        state.addRecord(record)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history[0].text, "テスト文字列")
    }

    @MainActor
    func testHistoryLimit() {
        let state = AppState()
        for i in 0..<60 {
            let record = TranscriptionRecord(
                text: "Record \(i)",
                date: Date(),
                duration: 1.0,
                provider: .openAI
            )
            state.addRecord(record)
        }
        XCTAssertEqual(state.history.count, 50)
        XCTAssertEqual(state.history[0].text, "Record 59")
    }
}
