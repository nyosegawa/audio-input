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

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private(set) var recordingURL: URL?
    private var startTime: Date?

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var rawRMS: Float = 0.0

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
                self?.rawRMS = rms
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
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            try? FileManager.default.removeItem(at: url)
            throw error
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

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        audioFile = nil
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
