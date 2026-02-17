import SwiftUI

struct HistoryView: View {
    let records: [TranscriptionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if records.isEmpty {
                Text("履歴なし")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(records) { record in
                            HistoryRow(record: record)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 300)
    }
}

struct HistoryRow: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.text)
                .font(.system(size: 12))
                .lineLimit(3)

            HStack {
                Text(record.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("\(String(format: "%.1f", record.duration))秒")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
