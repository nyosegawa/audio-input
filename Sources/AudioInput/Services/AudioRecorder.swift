@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool
}

enum RecordingError: Error, LocalizedError {
    case deviceSelectionFailed
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .deviceSelectionFailed: "入力デバイスの設定に失敗しました"
        case .deviceNotAvailable: "選択した入力デバイスが見つかりません。システムデフォルトを使用します"
        }
    }
}

/// Holds all state accessed from the audio tap callback thread.
/// @unchecked Sendable because all mutable state is protected by NSLock or single-writer.
/// This prevents Swift 6 from inserting MainActor isolation checks in the tap closure.
private final class AudioTapState: @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [Float] = []
    private var _audioLevel: Float = 0
    private var _rawRMS: Float = 0

    // Audio processing state (set once before tap starts, read from tap callback)
    var audioFile: AVAudioFile?
    var converter: AVAudioConverter?
    var outputFormat: AVAudioFormat?
    var sampleRateRatio: Double = 1.0

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return _samples
    }

    var audioLevel: Float {
        get { lock.lock(); defer { lock.unlock() }; return _audioLevel }
        set { lock.lock(); _audioLevel = newValue; lock.unlock() }
    }

    var rawRMS: Float {
        get { lock.lock(); defer { lock.unlock() }; return _rawRMS }
        set { lock.lock(); _rawRMS = newValue; lock.unlock() }
    }

    func appendSamples(_ newSamples: [Float]) {
        lock.lock()
        _samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func clearSamples() {
        lock.lock()
        _samples.removeAll()
        lock.unlock()
    }

    func reset() {
        audioFile = nil
        converter = nil
        outputFormat = nil
        sampleRateRatio = 1.0
        clearSamples()
        audioLevel = 0
        rawRMS = 0
    }
}

/// Install audio tap in a nonisolated context so the closure does NOT inherit
/// @MainActor isolation. This prevents Swift 6 runtime isolation checks on the
/// audio callback thread (RealtimeMessenger.mServiceQueue).
private func installAudioTap(
    on inputNode: AVAudioInputNode,
    format: AVAudioFormat,
    tapState: AudioTapState
) {
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        tapState.audioLevel = max(0, min(1, rms * 5))
        tapState.rawRMS = rms

        guard let outFmt = tapState.outputFormat,
              let conv = tapState.converter
        else { return }
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * tapState.sampleRateRatio))
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outFmt, frameCapacity: outputFrameCapacity)
        else { return }

        var error: NSError?
        let inputBuffer = buffer
        nonisolated(unsafe) var gotData = false
        conv.convert(to: outputBuffer, error: &error) { _, status in
            if gotData {
                status.pointee = .noDataNow
                return nil
            }
            gotData = true
            status.pointee = .haveData
            return inputBuffer
        }

        if error == nil, outputBuffer.frameLength > 0 {
            try? tapState.audioFile?.write(from: outputBuffer)

            if let floatData = outputBuffer.floatChannelData?[0] {
                let count = Int(outputBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: floatData, count: count))
                tapState.appendSamples(samples)
            }
        }
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private let tapState = AudioTapState()
    private var levelTimer: Timer?
    private(set) var recordingURL: URL?
    private var startTime: Date?

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var rawRMS: Float = 0.0

    /// Get a copy of accumulated 16kHz mono float samples for streaming transcription
    /// Thread-safe: can be called from any isolation context
    nonisolated var audioSamples: [Float] {
        tapState.samples
    }

    var recordingDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Device Enumeration

    static func availableInputDevices() -> [AudioInputDevice] {
        // Get default input device
        var defaultDeviceID: AudioDeviceID = 0
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress, 0, nil, &propSize, &defaultDeviceID
        )

        // Get all device IDs
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        // Filter to input devices and get names
        var result: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputChannels(deviceID: deviceID) else { continue }
            let name = deviceName(deviceID: deviceID) ?? "Unknown Device"
            result.append(AudioInputDevice(
                id: deviceID,
                name: name,
                isDefault: deviceID == defaultDeviceID
            ))
        }
        return result
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, bufferListPointer
        ) == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, &nameRef
        ) == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }
        return name as String
    }

    // MARK: - Recording

    func startRecording(inputDeviceID: AudioDeviceID? = nil) throws -> URL {
        tapState.reset()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_input_\(UUID().uuidString).wav")

        let engine = AVAudioEngine()

        // Set input device if specified
        if let deviceID = inputDeviceID {
            guard let audioUnit = engine.inputNode.audioUnit else {
                throw RecordingError.deviceSelectionFailed
            }
            var mutableDeviceID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw RecordingError.deviceSelectionFailed
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // File format on disk: 16kHz 16-bit int PCM mono WAV
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        // Processing format: Float32 at 16kHz mono.
        // AVAudioFile's default processingFormat is Float32, so buffers must match.
        // Using Float32 also lets us read floatChannelData for streaming transcription.
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: recordingFormat, to: outputFormat)!

        tapState.audioFile = try AVAudioFile(
            forWriting: url, settings: fileSettings,
            commonFormat: .pcmFormatFloat32, interleaved: false)
        tapState.converter = converter
        tapState.outputFormat = outputFormat
        tapState.sampleRateRatio = outputFormat.sampleRate / recordingFormat.sampleRate

        // Install tap via nonisolated free function so the closure is created
        // outside @MainActor context, preventing Swift 6 runtime isolation checks.
        installAudioTap(on: inputNode, format: recordingFormat, tapState: tapState)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            tapState.audioFile = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        // Poll audio levels from tapState and update @Published properties on main thread.
        // Use Task { @MainActor in } instead of MainActor.assumeIsolated because
        // Timer callbacks lack a Swift Task context, causing swift_task_isMainExecutorImpl
        // to crash on macOS 26 when checking executor identity.
        let pollTapState = self.tapState
        self.levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.audioLevel = pollTapState.audioLevel
                self?.rawRMS = pollTapState.rawRMS
            }
        }

        self.audioEngine = engine
        self.recordingURL = url
        self.startTime = Date()
        self.isRecording = true

        return url
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let engine = audioEngine, let url = recordingURL else { return nil }

        let duration = recordingDuration

        levelTimer?.invalidate()
        levelTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        tapState.reset()
        audioEngine = nil
        isRecording = false
        audioLevel = 0
        rawRMS = 0
        startTime = nil

        return (url: url, duration: duration)
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
