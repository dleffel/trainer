import SwiftUI

struct DebugMenuView: View {
    @State private var logs: [APILogEntry] = []
    @State private var filteredLogs: [APILogEntry] = []
    @State private var searchText = ""
    @State private var selectedStatusFilter: StatusFilter = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var showingClearConfirmation = false
    @State private var showingExportSheet = false
    @State private var selectedLog: APILogEntry?
    
    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case success = "Success (2xx)"
        case clientError = "Client Error (4xx)"
        case serverError = "Server Error (5xx)"
        case failed = "Failed"
        
        func matches(_ log: APILogEntry) -> Bool {
            switch self {
            case .all:
                return true
            case .success:
                return log.responseStatusCode.map { (200...299).contains($0) } ?? false
            case .clientError:
                return log.responseStatusCode.map { (400...499).contains($0) } ?? false
            case .serverError:
                return log.responseStatusCode.map { (500...599).contains($0) } ?? false
            case .failed:
                return log.error != nil || log.responseStatusCode == nil
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case slowest = "Slowest First"
        case fastest = "Fastest First"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                
                if filteredLogs.isEmpty {
                    emptyState
                } else {
                    logsList
                }
                
                bottomBar
            }
            .navigationTitle("API Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export Logs", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear All Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            loadLogs()
        }
        .sheet(item: $selectedLog) { log in
            NavigationStack {
                APILogDetailView(log: log)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog("Clear All Logs?", isPresented: $showingClearConfirmation) {
            Button("Clear All Logs", role: .destructive) {
                APILogger.shared.clearAllLogs()
                loadLogs()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportOptionsView(logs: filteredLogs)
        }
    }
    
    // MARK: - Views
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search URLs or response content", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { _, _ in
                        applyFilters()
                    }
            }
            .padding(.horizontal)
            
            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Status filter
                    Picker("Status", selection: $selectedStatusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedStatusFilter) { _, _ in
                        applyFilters()
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Sort order
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sortOrder) { _, _ in
                        applyFilters()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var logsList: some View {
        List(filteredLogs) { log in
            Button {
                selectedLog = log
            } label: {
                APILogRowView(log: log)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Logs Found")
                .font(.headline)
            
            Text(searchText.isEmpty ? "No API requests have been logged yet." : "Try adjusting your search or filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var bottomBar: some View {
        HStack {
            let info = APILogger.shared.getStorageInfo()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(info.logCount) logs")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if let oldest = info.oldestLog, let newest = info.newestLog {
                    Text("\(formatDate(oldest)) - \(formatDate(newest))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                loadLogs()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Functions
    
    private func loadLogs() {
        logs = APILogger.shared.getAllLogs()
        applyFilters()
    }
    
    private func applyFilters() {
        var filtered = logs
        
        // Apply status filter
        filtered = filtered.filter { selectedStatusFilter.matches($0) }
        
        // Apply search
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter { log in
                log.requestURL.lowercased().contains(searchLower) ||
                log.responseBodyString?.lowercased().contains(searchLower) ?? false ||
                log.error?.lowercased().contains(searchLower) ?? false
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .newest:
            filtered.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            filtered.sort { $0.timestamp < $1.timestamp }
        case .slowest:
            filtered.sort { $0.duration > $1.duration }
        case .fastest:
            filtered.sort { $0.duration < $1.duration }
        }
        
        filteredLogs = filtered
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Row View

struct APILogRowView: View {
    let log: APILogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                // Method
                Text(log.requestMethod)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                // Timestamp
                Text(log.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Duration
                Text(log.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // URL
            Text(formatURL(log.requestURL))
                .font(.footnote)
                .lineLimit(1)
            
            HStack {
                // Status code
                if let statusCode = log.responseStatusCode {
                    Text("HTTP \(statusCode)")
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                        .fontWeight(.medium)
                }
                
                // Error indicator
                if let error = log.error {
                    Text("Error: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // API key preview
                if !log.apiKeyPreview.isEmpty {
                    Text("Key: ***\(log.apiKeyPreview)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        if log.error != nil {
            return .red
        }
        
        guard let statusCode = log.responseStatusCode else {
            return .orange
        }
        
        switch statusCode {
        case 200...299:
            return .green
        case 400...499:
            return .orange
        case 500...599:
            return .red
        default:
            return .gray
        }
    }
    
    private func formatURL(_ url: String) -> String {
        // Remove common prefixes for cleaner display
        return url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "api.openai.com/", with: "")
            .replacingOccurrences(of: "openrouter.ai/", with: "")
    }
}

#Preview {
    DebugMenuView()
}