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

    // MARK: - History Persistence

    func testTranscriptionRecordCodable() throws {
        let record = TranscriptionRecord(
            text: "テスト文字列",
            date: Date(timeIntervalSince1970: 1700000000),
            duration: 3.5,
            provider: .openAI
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TranscriptionRecord.self, from: data)
        XCTAssertEqual(decoded.text, record.text)
        XCTAssertEqual(decoded.date.timeIntervalSince1970, record.date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.duration, record.duration, accuracy: 0.001)
        XCTAssertEqual(decoded.provider, record.provider)
    }

    func testTranscriptionRecordCodableGemini() throws {
        let record = TranscriptionRecord(
            text: "Geminiテスト",
            date: Date(),
            duration: 1.2,
            provider: .gemini
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TranscriptionRecord.self, from: data)
        XCTAssertEqual(decoded.provider, .gemini)
    }

    @MainActor
    func testSaveAndLoadHistory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioInputTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("history.json")

        let state = AppState()
        state.addRecord(TranscriptionRecord(text: "First", date: Date(), duration: 1.0, provider: .openAI))
        state.addRecord(TranscriptionRecord(text: "Second", date: Date(), duration: 2.0, provider: .gemini))

        state.saveHistory(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        let state2 = AppState()
        state2.loadHistory(from: file)
        XCTAssertEqual(state2.history.count, 2)
        XCTAssertEqual(state2.history[0].text, "Second")
        XCTAssertEqual(state2.history[1].text, "First")
    }

    @MainActor
    func testLoadHistoryFromMissingFile() {
        let state = AppState()
        let nonexistent = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).json")
        state.loadHistory(from: nonexistent)
        XCTAssertTrue(state.history.isEmpty)
    }

    @MainActor
    func testSuccessStatus() {
        let state = AppState()
        state.status = .success("テスト完了")
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertEqual(state.statusText, "完了")
    }
}
