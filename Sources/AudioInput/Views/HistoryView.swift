import SwiftUI

struct HistoryView: View {
    let records: [TranscriptionRecord]
    let onExport: (() -> Void)?
    @State private var searchText = ""

    init(records: [TranscriptionRecord], onExport: (() -> Void)? = nil) {
        self.records = records
        self.onExport = onExport
    }

    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty { return records }
        return records.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("検索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if let onExport = onExport, !records.isEmpty {
                    Button {
                        onExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("履歴をエクスポート")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredRecords.isEmpty {
                VStack {
                    Spacer()
                    Text(records.isEmpty ? "履歴なし" : "一致する結果なし")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredRecords) { record in
                            HistoryRow(record: record, searchText: searchText)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 350)
    }
}

struct HistoryRow: View {
    let record: TranscriptionRecord
    var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.text)
                .font(.system(size: 12))
                .lineLimit(3)

            HStack {
                Text(record.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("\(String(format: "%.1f", record.duration))秒")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(record.provider.rawValue)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("コピー")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
