import AVFoundation
import CWhisper
import Foundation

// MARK: - WhisperContext Actor

actor WhisperContext {
    private nonisolated(unsafe) var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func fullTranscribe(samples: [Float], language: String?) {
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false

        let start = CFAbsoluteTimeGetCurrent()
        NSLog("[WHISPER] fullTranscribe: %d samples (%.2fs audio), lang=%@, threads=%d",
              samples.count, Float(samples.count) / 16000.0,
              language ?? "auto", maxThreads)

        if let language = language {
            language.withCString { lang in
                params.language = lang
                _runFull(params: params, samples: samples)
            }
        } else {
            params.language = nil
            _runFull(params: params, samples: samples)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        NSLog("[WHISPER] fullTranscribe completed in %.3fs", elapsed)
    }

    private func _runFull(params: whisper_full_params, samples: [Float]) {
        let p = params
        samples.withUnsafeBufferPointer { buf in
            if whisper_full(context, p, buf.baseAddress, Int32(buf.count)) != 0 {
                NSLog("[WHISPER] whisper_full failed")
            }
        }
    }

    func getTranscription() -> String {
        var text = ""
        let n = whisper_full_n_segments(context)
        for i in 0..<n {
            if let cStr = whisper_full_get_segment_text(context, i) {
                text += String(cString: cStr)
            }
        }
        return text
    }

    static func createContext(path: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw TranscriptionError.apiError("whisper.cppモデルの初期化に失敗: \(path)")
        }
        return WhisperContext(context: ctx)
    }
}

private func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}

// MARK: - WhisperTranscriber

@MainActor
final class WhisperTranscriber: ObservableObject {
    private var whisperContext: WhisperContext?
    private var streamingTask: Task<Void, Never>?

    @Published var isModelLoaded = false
    @Published var isStreamingModelLoaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var loadedModel: WhisperModel?

    /// Base directory for model files
    private var modelsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AudioInput/models")
    }

    private func modelFilePath(_ model: WhisperModel) -> URL {
        modelsDir.appendingPathComponent(model.filename)
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelFilePath(model).path)
    }

    // MARK: - Download

    func downloadModel(_ model: WhisperModel, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        isDownloading = true
        downloadProgress = 0.0

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destination = modelFilePath(model)
        let url = model.downloadURL

        NSLog("[WHISPER] Downloading %@ from %@", model.filename, url.absoluteString)

        // Use delegate-based download for progress reporting
        let delegate = DownloadProgressDelegate { fraction in
            Task { @MainActor in
                onProgress(fraction)
                self.downloadProgress = fraction
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url)
        session.invalidateAndCancel()

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            isDownloading = false
            throw TranscriptionError.apiError("モデルのダウンロードに失敗しました (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }

        // Move downloaded file to final location
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        isDownloading = false
        downloadProgress = 1.0
        NSLog("[WHISPER] Download complete: %@ (%lld bytes)", destination.path, httpResponse.expectedContentLength)
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModel) async throws {
        let path = modelFilePath(model).path
        NSLog("[WHISPER] Loading model from: %@", path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriptionError.apiError("モデルがダウンロードされていません: \(model.displayName)")
        }

        let ctx = try await Task.detached {
            try WhisperContext.createContext(path: path)
        }.value

        whisperContext = ctx
        isModelLoaded = true
        isStreamingModelLoaded = true
        loadedModel = model
        NSLog("[WHISPER] Model loaded successfully: %@", model.rawValue)
    }

    func ensureModelReady(_ model: WhisperModel, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        if !isModelDownloaded(model) {
            NSLog("[WHISPER] Model not found, downloading...")
            try await downloadModel(model, onProgress: onProgress)
        }
        if whisperContext == nil || !isModelLoaded {
            try await loadModel(model)
        }
    }

    /// No-op: whisper.cpp uses a single model for both streaming and final transcription
    func loadStreamingModelIfNeeded() {}

    // MARK: - Batch Transcription

    func transcribe(audioURL: URL, language: String) async throws -> String {
        guard let ctx = whisperContext else {
            throw TranscriptionError.apiError("whisper.cppモデルが読み込まれていません")
        }

        let samples = try loadAudioSamples(from: audioURL)

        let lang = language == "auto" ? nil : language
        await ctx.fullTranscribe(samples: samples, language: lang)
        let text = await ctx.getTranscription()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        return text
    }

    /// Load audio file as 16kHz mono Float samples
    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw TranscriptionError.apiError("オーディオフォーマットの作成に失敗")
        }

        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let ratio = 16000.0 / file.processingFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(file.length) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: estimatedFrames) else {
            throw TranscriptionError.apiError("オーディオバッファの作成に失敗")
        }

        nonisolated(unsafe) var isDone = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if isDone {
                outStatus.pointee = .endOfStream
                return nil
            }
            let frameCount = min(AVAudioFrameCount(4096), AVAudioFrameCount(file.length - file.framePosition))
            if frameCount == 0 {
                outStatus.pointee = .endOfStream
                isDone = true
                return nil
            }
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: buf)
                outStatus.pointee = .haveData
                return buf
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error {
            throw TranscriptionError.apiError("オーディオ変換エラー: \(error.localizedDescription)")
        }

        guard let floatData = outputBuffer.floatChannelData else {
            throw TranscriptionError.apiError("オーディオデータの取得に失敗")
        }
        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
    }

    // MARK: - Streaming Transcription

    func startStreamingTranscription(
        audioSamplesProvider: @escaping @Sendable () -> [Float],
        language: String,
        onUpdate: @escaping @MainActor @Sendable (_ confirmed: String, _ hypothesis: String) -> Void
    ) {
        stopStreamingTranscription()

        guard let ctx = whisperContext else {
            NSLog("[STREAM] No whisper context available")
            return
        }

        let lang = language == "auto" ? nil : language

        streamingTask = Task.detached {
            var prevText = ""
            var confirmedNormLen = 0
            var lastSampleCount = 0
            // Minimum samples before first inference: 1.5s at 16kHz
            let minSamplesForFirstInference = 24000
            // Minimum new samples between inferences: 0.5s at 16kHz
            let minNewSamples = 8000

            NSLog("[STREAM] Streaming task started")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }

                let samples = audioSamplesProvider()

                // Wait for enough audio before first inference to avoid hallucination
                if lastSampleCount == 0 && samples.count < minSamplesForFirstInference {
                    continue
                }

                // Need enough new samples
                guard samples.count > lastSampleCount + minNewSamples else { continue }

                NSLog("[STREAM] Transcribing %d samples (%.2fs audio), +%d new",
                      samples.count, Float(samples.count) / 16000.0,
                      samples.count - lastSampleCount)

                lastSampleCount = samples.count

                await ctx.fullTranscribe(samples: samples, language: lang)
                guard !Task.isCancelled else { break }
                let currentText = await ctx.getTranscription()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                NSLog("[STREAM] Raw transcription: '%@'", currentText)

                // Filter out known hallucinations (common with short/silent audio)
                if Self.isHallucination(currentText) {
                    NSLog("[STREAM] Filtered hallucination: '%@'", currentText)
                    continue
                }

                guard !currentText.isEmpty else { continue }

                // Split current text into confirmed (stable) and hypothesis (may change)
                let (confirmed, hypothesis, newNormLen) = Self.splitConfirmedHypothesis(
                    prevText: prevText,
                    currentText: currentText,
                    previousConfirmedNormLen: confirmedNormLen
                )

                confirmedNormLen = newNormLen
                prevText = currentText

                NSLog("[STREAM] confirmed='%@' hypothesis='%@'", confirmed, hypothesis)
                await onUpdate(confirmed, hypothesis)
            }
            NSLog("[STREAM] Streaming task ended")
        }
    }

    func stopStreamingTranscription() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    /// Detect common Whisper hallucinations (repeated phrases generated from silence/noise)
    private nonisolated static func isHallucination(_ text: String) -> Bool {
        let hallucinations = [
            "ご視聴ありがとうございました",
            "ありがとうございました",
            "チャンネル登録お願いします",
            "お疲れ様でした",
            "字幕をご覧いただけます",
            "Thank you for watching",
            "Thanks for watching",
            "Subscribe",
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。、.!！"))
        return hallucinations.contains { trimmed == $0 }
    }

    /// Split transcription into confirmed (stable across runs) and hypothesis (may change).
    /// Uses normalized comparison that ignores punctuation/spaces, since whisper.cpp
    /// adds or removes punctuation between inference runs on the same audio.
    /// Returns (confirmed, hypothesis, confirmedNormalizedLength).
    private nonisolated static func splitConfirmedHypothesis(
        prevText: String,
        currentText: String,
        previousConfirmedNormLen: Int
    ) -> (confirmed: String, hypothesis: String, confirmedNormLen: Int) {
        // Normalize: remove punctuation and whitespace for comparison
        let prevNorm = Array(prevText.filter { !$0.isPunctuation && !$0.isWhitespace })
        let currNorm = Array(currentText.filter { !$0.isPunctuation && !$0.isWhitespace })

        // Find common prefix on normalized text
        let minLen = min(prevNorm.count, currNorm.count)
        var commonNormLen = 0
        while commonNormLen < minLen && prevNorm[commonNormLen] == currNorm[commonNormLen] {
            commonNormLen += 1
        }

        // Only grow confirmed, never shrink
        let targetNormLen = max(commonNormLen, previousConfirmedNormLen)
        // But don't exceed what's actually in current text
        let effectiveNormLen = min(targetNormLen, currNorm.count)

        // Map normalized character count back to position in original currentText
        var normCount = 0
        var splitIdx = currentText.startIndex
        for ch in currentText {
            if normCount >= effectiveNormLen { break }
            splitIdx = currentText.index(after: splitIdx)
            if !ch.isPunctuation && !ch.isWhitespace {
                normCount += 1
            }
        }
        // Include any trailing punctuation/space after the last confirmed character
        while splitIdx < currentText.endIndex {
            let ch = currentText[splitIdx]
            if ch.isPunctuation || ch.isWhitespace {
                splitIdx = currentText.index(after: splitIdx)
            } else {
                break
            }
        }

        let confirmed = String(currentText[currentText.startIndex..<splitIdx])
        let hypothesis = String(currentText[splitIdx...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (confirmed, hypothesis, effectiveNormLen)
    }

    // MARK: - Cleanup

    func unloadModel() {
        whisperContext = nil
        isModelLoaded = false
        isStreamingModelLoaded = false
        loadedModel = nil
    }

    func unloadStreamingModel() {
        // No-op: single model
    }

    func deleteModel(_ model: WhisperModel) throws {
        let path = modelFilePath(model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(fraction)
        } else {
            // Content-Length unknown: use response header if available
            if let response = downloadTask.response as? HTTPURLResponse,
               let lengthStr = response.value(forHTTPHeaderField: "Content-Length"),
               let totalBytes = Int64(lengthStr), totalBytes > 0 {
                let fraction = Double(totalBytesWritten) / Double(totalBytes)
                onProgress(fraction)
            }
            // If still unknown, leave progress at 0 (indeterminate spinner shown)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download call
    }
}
