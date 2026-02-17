@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    var recordingDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func startRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_input_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create WAV file for writing
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let outputFormat = AVAudioFormat(settings: settings)!
        let converter = AVAudioConverter(from: recordingFormat, to: outputFormat)!

        audioFile = try AVAudioFile(forWriting: url, settings: settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) {
            [weak self] buffer, _ in
            // Calculate audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            let level = max(0, min(1, rms * 5))

            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }

            // Convert and write to file
            let ratio = outputFormat.sampleRate / recordingFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(
                ceil(Double(buffer.frameLength) * ratio))
            guard
                let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat, frameCapacity: outputFrameCapacity)
            else { return }

            var error: NSError?
            let inputBuffer = buffer
            nonisolated(unsafe) var gotData = false
            converter.convert(to: outputBuffer, error: &error) { _, status in
                if gotData {
                    status.pointee = .noDataNow
                    return nil
                }
                gotData = true
                status.pointee = .haveData
                return inputBuffer
            }

            if error == nil, outputBuffer.frameLength > 0 {
                try? self?.audioFile?.write(from: outputBuffer)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recordingURL = url
        self.startTime = Date()
        self.isRecording = true

        return url
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let engine = audioEngine, let url = recordingURL else { return nil }

        let duration = recordingDuration

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        audioFile = nil
        audioEngine = nil
        isRecording = false
        audioLevel = 0
        startTime = nil

        return (url: url, duration: duration)
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
