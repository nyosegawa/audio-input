import Foundation
import Observation
import SwiftUI

enum AppStatus: Sendable {
    case idle
    case recording
    case transcribing
    case processing
    case success(String)
    case error(String)
}

struct TranscriptionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let date: Date
    let duration: TimeInterval
    let provider: TranscriptionProvider

    init(text: String, date: Date, duration: TimeInterval, provider: TranscriptionProvider) {
        self.id = UUID()
        self.text = text
        self.date = date
        self.duration = duration
        self.provider = provider
    }
}

enum ModelDownloadState: Sendable {
    case notDownloaded
    case downloading(Double)
    case loading
    case downloaded
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

@MainActor
@Observable
final class AppState {
    var status: AppStatus = .idle
    var audioLevel: Float = 0.0
    var recordingStartTime: Date? = nil
    var confirmedStreamingText: String = ""
    var hypothesisStreamingText: String = ""
    var modelDownloadState: ModelDownloadState = .notDownloaded
    var history: [TranscriptionRecord] = []
    var micPermission: PermissionStatus = .notDetermined
    var accessibilityPermission: PermissionStatus = .notDetermined

    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = status { return true }
        if case .processing = status { return true }
        return false
    }

    var isBusy: Bool {
        isRecording || isTranscribing
    }

    var statusText: String {
        switch status {
        case .idle: "待機中"
        case .recording: "録音中..."
        case .transcribing: "文字起こし中..."
        case .processing: "テキスト整形中..."
        case .success: "完了"
        case .error(let msg): "エラー: \(msg)"
        }
    }

    func addRecord(_ record: TranscriptionRecord) {
        history.insert(record, at: 0)
        if history.count > 50 {
            history.removeLast()
        }
        saveHistory()
    }

    // MARK: - History Persistence

    private static var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AudioInput")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func saveHistory(to url: URL? = nil) {
        let fileURL = url ?? Self.historyFileURL
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func loadHistory(from url: URL? = nil) {
        let fileURL = url ?? Self.historyFileURL
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) else { return }
        history = records
    }
}
