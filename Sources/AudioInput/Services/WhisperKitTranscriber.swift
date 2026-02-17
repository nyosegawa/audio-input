import Foundation
import WhisperKit

/// Thread-safe holder for WhisperKit instance (non-Sendable)
final class WhisperKitHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _kit: WhisperKit?

    var kit: WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return _kit
    }

    func set(_ newKit: WhisperKit?) {
        lock.lock()
        _kit = newKit
        lock.unlock()
    }
}

@MainActor
final class WhisperKitTranscriber: ObservableObject {
    private let holder = WhisperKitHolder()
    private var streamingTask: Task<Void, Never>?

    @Published var isModelLoaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0

    private var modelFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AudioInput/models")
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let folder = modelFolder.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: folder.path)
    }

    // MARK: - Model Download

    func downloadModel(_ model: WhisperModel, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        isDownloading = true
        downloadProgress = 0.0

        let modelBase = modelFolder
        let modelRaw = model.rawValue

        try FileManager.default.createDirectory(at: modelBase, withIntermediateDirectories: true)

        let progressCallback: @Sendable (Progress) -> Void = { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                onProgress(fraction)
            }
        }

        _ = try await WhisperKit.download(
            variant: modelRaw,
            downloadBase: modelBase,
            useBackgroundSession: false,
            progressCallback: progressCallback
        )

        isDownloading = false
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModel) async throws {
        let folder = modelFolder.appendingPathComponent(model.rawValue)

        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw TranscriptionError.apiError("モデルがダウンロードされていません: \(model.displayName)")
        }

        let config = WhisperKitConfig(
            model: model.rawValue,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        holder.set(kit)
        isModelLoaded = true
    }

    func ensureModelReady(_ model: WhisperModel, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        if !isModelDownloaded(model) {
            try await downloadModel(model, onProgress: onProgress)
        }
        if holder.kit == nil || !isModelLoaded {
            try await loadModel(model)
        }
    }

    // MARK: - Batch Transcription

    func transcribe(audioURL: URL, language: String) async throws -> String {
        guard holder.kit != nil else {
            throw TranscriptionError.apiError("WhisperKitモデルが読み込まれていません")
        }

        let options = DecodingOptions(
            language: language == "auto" ? nil : language,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true
        )

        let audioPath = audioURL.path
        let holderRef = holder

        let results = try await Task.detached {
            guard let k = holderRef.kit else {
                throw TranscriptionError.apiError("WhisperKitモデルが読み込まれていません")
            }
            return try await k.transcribe(
                audioPath: audioPath,
                decodeOptions: options
            )
        }.value

        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        return text
    }

    // MARK: - Streaming Transcription (during recording)

    func startStreamingTranscription(
        audioSamplesProvider: @escaping @Sendable () -> [Float],
        language: String,
        onText: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stopStreamingTranscription()

        let holderRef = holder
        let lang = language == "auto" ? nil : language

        streamingTask = Task.detached {
            var lastSampleCount = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { break }

                let samples = audioSamplesProvider()
                guard samples.count > lastSampleCount + 8000 else { continue }
                lastSampleCount = samples.count

                guard let kit = holderRef.kit else { break }

                do {
                    let options = DecodingOptions(
                        language: lang,
                        temperature: 0.0,
                        usePrefillPrompt: true
                    )
                    let results = try await kit.transcribe(
                        audioArray: samples,
                        decodeOptions: options
                    )
                    guard !Task.isCancelled else { break }
                    let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        await onText(text)
                    }
                } catch {
                    continue
                }
            }
        }
    }

    func stopStreamingTranscription() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    // MARK: - Cleanup

    func unloadModel() {
        holder.set(nil)
        isModelLoaded = false
    }

    func deleteModel(_ model: WhisperModel) throws {
        let folder = modelFolder.appendingPathComponent(model.rawValue)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }
}
