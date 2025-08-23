import SwiftUI

struct ExportOptionsView: View {
    let logs: [APILogEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .json
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Format")
                        .font(.headline)
                    
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Export info
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(logs.count) logs will be exported", systemImage: "doc.text")
                    
                    if let oldest = logs.min(by: { $0.timestamp < $1.timestamp }),
                       let newest = logs.max(by: { $0.timestamp < $1.timestamp }) {
                        Label(
                            "From \(formatDate(oldest.timestamp)) to \(formatDate(newest.timestamp))",
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                
                Spacer()
                
                // Export button
                Button {
                    exportLogs()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .disabled(isExporting)
            }
            .padding(.vertical)
            .navigationTitle("Export Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: LogsDocument(logs: logs, format: selectedFormat),
            contentType: selectedFormat == .json ? .json : .commaSeparatedText,
            defaultFilename: "api_logs_\(dateString()).\(selectedFormat.fileExtension)"
        ) { result in
            switch result {
            case .success(let url):
                exportedFileURL = url
            case .failure(let error):
                print("Export failed: \(error)")
            }
            dismiss()
        }
    }
    
    private func exportLogs() {
        isExporting = true
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Document Type

struct LogsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    
    let logs: [APILogEntry]
    let format: ExportOptionsView.ExportFormat
    
    init(logs: [APILogEntry], format: ExportOptionsView.ExportFormat) {
        self.logs = logs
        self.format = format
    }
    
    init(configuration: ReadConfiguration) throws {
        // We only support writing, not reading
        self.logs = []
        self.format = .json
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(logs)
            
        case .csv:
            var csv = "Timestamp,Method,URL,Status Code,Duration (s),Error,API Key Preview\n"
            
            for log in logs {
                let timestamp = ISO8601DateFormatter().string(from: log.timestamp)
                let method = log.requestMethod
                let url = escapeCSV(log.requestURL)
                let statusCode = log.responseStatusCode.map(String.init) ?? ""
                let duration = String(format: "%.3f", log.duration)
                let error = escapeCSV(log.error ?? "")
                let apiKey = log.apiKeyPreview.isEmpty ? "" : "***\(log.apiKeyPreview)"
                
                csv += "\(timestamp),\(method),\(url),\(statusCode),\(duration),\(error),\(apiKey)\n"
            }
            
            data = csv.data(using: .utf8) ?? Data()
        }
        
        return FileWrapper(regularFileWithContents: data)
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}