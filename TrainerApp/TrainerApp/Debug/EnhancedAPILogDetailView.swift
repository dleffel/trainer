import SwiftUI

struct EnhancedAPILogDetailView: View {
    let log: APILogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var copiedToClipboard = false
    @State private var isRefreshing = false
    
    // Timer for auto-refresh if request is active
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status Banner
                statusBanner
                
                // Tab View
                TabView(selection: $selectedTab) {
                    overviewTab
                        .tabItem {
                            Label("Overview", systemImage: "info.circle")
                        }
                        .tag(0)
                    
                    requestTab
                        .tabItem {
                            Label("Request", systemImage: "arrow.up.circle")
                        }
                        .tag(1)
                    
                    responseTab
                        .tabItem {
                            Label("Response", systemImage: "arrow.down.circle")
                        }
                        .tag(2)
                    
                    curlTab
                        .tabItem {
                            Label("cURL", systemImage: "terminal")
                        }
                        .tag(3)
                }
            }
            .navigationTitle("API Log Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if log.isActive {
                        Button(action: refresh) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isRefreshing)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if copiedToClipboard {
                    copyNotification
                }
            }
            .onAppear {
                if log.isActive {
                    startAutoRefresh()
                }
            }
            .onDisappear {
                stopAutoRefresh()
            }
        }
    }
    
    // MARK: - Status Banner
    
    private var statusBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Text(log.statusDescription)
                    .font(.headline)
                    .foregroundColor(statusTextColor)
                
                Spacer()
                
                if let duration = log.duration, duration > 0 {
                    Text(log.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if log.phase == .streaming, let bytes = log.formattedBytesReceived {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Received: \(bytes)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(statusBackgroundColor)
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Request Summary
                detailSection("Request Summary") {
                    DetailRow(label: "Method", value: log.requestMethod)
                    DetailRow(label: "URL", value: log.requestURL)
                    DetailRow(label: "Timestamp", value: log.formattedTimestamp)
                    if !log.apiKeyPreview.isEmpty {
                        DetailRow(label: "API Key", value: "****\(log.apiKeyPreview)")
                    }
                }
                
                // Response Summary
                if log.phase != .sent {
                    detailSection("Response Summary") {
                        if let statusCode = log.responseStatusCode {
                            HStack {
                                Text("Status Code")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(statusCode)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(statusColor(for: statusCode))
                            }
                        }
                        
                        if let phase = log.phase {
                            DetailRow(label: "Phase", value: phase.rawValue)
                        }
                        
                        if let bytes = log.formattedBytesReceived {
                            DetailRow(label: "Data Received", value: bytes)
                        }
                        
                        DetailRow(label: "Duration", value: log.formattedDuration)
                        
                        if let error = log.error {
                            DetailRow(label: "Error", value: error)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                // Timeline
                if let phase = log.phase {
                    timelineSection(phase: phase)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Request Tab
    
    private var requestTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic Info
                detailSection("Request Info") {
                    DetailRow(label: "URL", value: log.requestURL)
                    DetailRow(label: "Method", value: log.requestMethod)
                    DetailRow(label: "Sent At", value: log.formattedTimestamp)
                }
                
                // Headers
                if !log.requestHeaders.isEmpty {
                    detailSection("Request Headers") {
                        ForEach(log.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            if key.lowercased() == "authorization" {
                                DetailRow(label: key, value: maskAuthorizationValue(value))
                            } else {
                                DetailRow(label: key, value: value)
                            }
                        }
                    }
                }
                
                // Body
                if let bodyString = log.requestBodyString {
                    detailSection("Request Body") {
                        codeBlock(bodyString, copyValue: bodyString)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Response Tab
    
    private var responseTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if log.phase == .sent {
                    // Waiting for response
                    VStack(spacing: 16) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Waiting for response...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if let duration = log.duration, duration > 0 {
                            Text("Elapsed: \(log.formattedDuration)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Response received
                    Group {
                        // Basic Info
                        detailSection("Response Info") {
                            if let statusCode = log.responseStatusCode {
                                HStack {
                                    Text("Status Code")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(statusCode)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(statusColor(for: statusCode))
                                }
                            }
                            
                            DetailRow(label: "Duration", value: log.formattedDuration)
                            
                            if let bytes = log.formattedBytesReceived {
                                DetailRow(label: "Size", value: bytes)
                            }
                            
                            if let error = log.error {
                                DetailRow(label: "Error", value: error)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        // Headers
                        if let headers = log.responseHeaders, !headers.isEmpty {
                            detailSection("Response Headers") {
                                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    DetailRow(label: key, value: value)
                                }
                            }
                        }
                        
                        // Body
                        if let bodyString = log.responseBodyString {
                            detailSection("Response Body") {
                                if log.phase == .streaming {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Streaming in progress...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        codeBlock(bodyString, copyValue: bodyString)
                                    }
                                } else {
                                    codeBlock(bodyString, copyValue: bodyString)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - cURL Tab
    
    private var curlTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Copy this command to replay the request in Terminal:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                codeBlock(log.curlCommand, copyValue: log.curlCommand)
            }
            .padding()
        }
    }
    
    // MARK: - Timeline Section
    
    private func timelineSection(phase: APILogEntry.APILogPhase) -> some View {
        detailSection("Timeline") {
            VStack(alignment: .leading, spacing: 12) {
                timelineItem(
                    title: "Request Sent",
                    time: log.formattedTimestamp,
                    isCompleted: true,
                    isActive: false
                )
                
                if phase != .sent {
                    let streamingStarted = phase == .streaming || phase == .completed || phase == .failed
                    timelineItem(
                        title: "Response Started",
                        time: streamingStarted ? "Started" : "Pending",
                        isCompleted: streamingStarted,
                        isActive: phase == .streaming
                    )
                }
                
                if phase == .completed || phase == .failed || phase == .timedOut {
                    timelineItem(
                        title: phase == .timedOut ? "Timed Out" : "Completed",
                        time: log.formattedDuration,
                        isCompleted: true,
                        isActive: false,
                        isError: phase == .failed || phase == .timedOut
                    )
                }
            }
        }
    }
    
    private func timelineItem(title: String, time: String, isCompleted: Bool, isActive: Bool, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            ZStack {
                Circle()
                    .fill(isError ? Color.red : (isCompleted ? Color.green : Color.gray.opacity(0.3)))
                    .frame(width: 12, height: 12)
                
                if isActive {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .scaleEffect(1.2)
                        .opacity(0.6)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isActive)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .medium : .regular)
                
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Views
    
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func codeBlock(_ code: String, copyValue: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                copyToClipboard(copyValue)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var copyNotification: some View {
        Text("Copied to Clipboard")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom)
    }
    
    // MARK: - Helper Functions
    
    private func maskAuthorizationValue(_ value: String) -> String {
        if value.hasPrefix("Bearer ") {
            let token = String(value.dropFirst(7))
            if token.count > 4 {
                let lastFour = String(token.suffix(4))
                return "Bearer ***\(lastFour)"
            }
        }
        return "***"
    }
    
    private func statusColor(for code: Int) -> Color {
        switch code {
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
    
    private var statusTextColor: Color {
        guard let phase = log.phase else { return .primary }
        
        switch phase {
        case .sent, .streaming:
            return .blue
        case .completed:
            return .green
        case .failed, .timedOut:
            return .red
        }
    }
    
    private var statusBackgroundColor: Color {
        guard let phase = log.phase else { return Color(.systemGray6) }
        
        switch phase {
        case .sent, .streaming:
            return Color.blue.opacity(0.1)
        case .completed:
            return Color.green.opacity(0.1)
        case .failed, .timedOut:
            return Color.red.opacity(0.1)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        withAnimation {
            copiedToClipboard = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if log.isActive {
                refresh()
            } else {
                stopAutoRefresh()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshing = false
    }
    
    private func refresh() {
        withAnimation {
            isRefreshing = true
        }
        
        // In a real implementation, this would fetch updated log data
        // For now, we'll just simulate a refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                isRefreshing = false
            }
        }
    }
}

// MARK: - Detail Row (Reused from original)

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}