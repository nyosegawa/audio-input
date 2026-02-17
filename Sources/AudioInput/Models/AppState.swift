import Foundation
import SwiftUI

enum AppStatus: Sendable {
    case idle
    case recording
    case transcribing
    case processing
    case success(String)
    case error(String)
}

struct TranscriptionRecord: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let date: Date
    let duration: TimeInterval
    let provider: TranscriptionProvider
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingStartTime: Date? = nil
    @Published var history: [TranscriptionRecord] = []

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
    }
}
