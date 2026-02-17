import SwiftUI

struct RecordingOverlay: View {
    let audioLevel: Float
    let status: AppStatus

    var body: some View {
        HStack(spacing: 12) {
            // Mic icon with pulse animation
            ZStack {
                Circle()
                    .fill(micColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .scaleEffect(isRecording ? 1.0 + CGFloat(audioLevel) * 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)

                Image(systemName: micIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(micColor)
            }

            // Status text
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            // Audio level bars
            if isRecording {
                AudioLevelBars(level: audioLevel)
                    .frame(width: 40, height: 20)
            }

            if isTranscribing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    private var isTranscribing: Bool {
        if case .transcribing = status { return true }
        return false
    }

    private var micColor: Color {
        switch status {
        case .recording: .red
        case .transcribing: .orange
        case .error: .red
        case .idle: .secondary
        }
    }

    private var micIconName: String {
        switch status {
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        default: "mic"
        }
    }

    private var statusText: String {
        switch status {
        case .recording: "録音中"
        case .transcribing: "文字起こし中..."
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
