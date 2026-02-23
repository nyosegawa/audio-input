import SwiftUI

struct RecordingOverlay: View {
    let audioLevel: Float
    let status: AppStatus
    let recordingStartTime: Date?
    let confirmedStreamingText: String
    let hypothesisStreamingText: String
    var processingError: String? = nil
    var style: OverlayStyle = .standard

    var body: some View {
        switch style {
        case .standard:
            standardOverlay
        case .compact:
            compactOverlay
        case .minimal:
            minimalOverlay
        }
    }

    // MARK: - Standard (full info)

    private var standardOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                micIndicator(size: 36, iconSize: 16)

                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                if isRecording, let start = recordingStartTime {
                    elapsedTimer(start: start, size: 13)
                }

                if isRecording {
                    AudioLevelBars(level: audioLevel)
                        .frame(width: 40, height: 20)
                }

                if case .success(let text) = status {
                    Text(text.count > 80 ? String(text.prefix(80)) + "..." : text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 180, alignment: .leading)
                }

                if isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let processingError = processingError, case .success = status {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text(processingError)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            if (!confirmedStreamingText.isEmpty || !hypothesisStreamingText.isEmpty) && (isRecording || isTranscribing) {
                (Text(confirmedStreamingText).fontWeight(.medium) +
                 Text(hypothesisStreamingText).foregroundStyle(.secondary))
                    .font(.system(size: 13))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    // MARK: - Compact

    private var compactOverlay: some View {
        HStack(spacing: 8) {
            micIndicator(size: 28, iconSize: 13)

            if isRecording, let start = recordingStartTime {
                elapsedTimer(start: start, size: 12)
            }

            if isRecording {
                AudioLevelBars(level: audioLevel)
                    .frame(width: 30, height: 14)
            }

            if isTranscribing {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if case .success(let text) = status {
                Text(text.count > 40 ? String(text.prefix(40)) + "..." : text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if case .error(let msg) = status {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    // MARK: - Minimal (dot)

    private var minimalOverlay: some View {
        ZStack {
            Circle()
                .fill(micColor.opacity(0.3))
                .frame(width: 32, height: 32)
                .scaleEffect(isRecording ? 1.0 + CGFloat(audioLevel) * 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: audioLevel)

            Circle()
                .fill(micColor)
                .frame(width: 16, height: 16)

            if isTranscribing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .shadow(color: micColor.opacity(0.4), radius: 8)
    }

    // MARK: - Shared Components

    private func micIndicator(size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(micColor.opacity(0.2))
                .frame(width: size, height: size)
                .scaleEffect(isRecording ? 1.0 + CGFloat(audioLevel) * 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: audioLevel)

            Image(systemName: micIconName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(micColor)
        }
    }

    private func elapsedTimer(start: Date, size: CGFloat) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed

    private var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    private var isTranscribing: Bool {
        switch status {
        case .transcribing, .processing: return true
        default: return false
        }
    }

    private var micColor: Color {
        switch status {
        case .recording: .red
        case .transcribing: .orange
        case .processing: .blue
        case .success: .green
        case .error: .red
        case .idle: .secondary
        }
    }

    private var micIconName: String {
        switch status {
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .processing: "text.badge.checkmark"
        case .success: "checkmark.circle.fill"
        default: "mic"
        }
    }

    private var statusText: String {
        switch status {
        case .recording: "録音中"
        case .transcribing: "文字起こし中..."
        case .processing: "テキスト整形中..."
        case .success: "完了"
        case .error(let msg): msg
        case .idle: ""
        }
    }
}

struct AudioLevelBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3)
                    .frame(height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / 5.0
        let activeLevel = max(0, level - threshold) / (1.0 - threshold)
        return CGFloat(4 + activeLevel * 16)
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / 5.0
        return level > threshold ? .red : .red.opacity(0.2)
    }
}
