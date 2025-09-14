import SwiftUI

struct APILogDetailView: View {
    let log: APILogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var copiedToClipboard = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            requestView
                .tabItem {
                    Label("Request", systemImage: "arrow.up.circle")
                }
                .tag(0)
            
            responseView
                .tabItem {
                    Label("Response", systemImage: "arrow.down.circle")
                }
                .tag(1)
            
            curlView
                .tabItem {
                    Label("cURL", systemImage: "terminal")
                }
                .tag(2)
        }
        .navigationTitle("API Log Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }
    
    // MARK: - Request View
    
    private var requestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic Info
                detailSection("Request Info") {
                    DetailRow(label: "URL", value: log.requestURL)
                    DetailRow(label: "Method", value: log.requestMethod)
                    DetailRow(label: "Timestamp", value: log.formattedTimestamp)
                }
                
                // Headers
                if !log.requestHeaders.isEmpty {
                    detailSection("Headers") {
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
                if let bodyString = log.formattedRequestBody {
                    detailSection("Body") {
                        codeBlock(bodyString, copyValue: log.requestBodyString ?? bodyString)
                    }
                }
                
                // Conversation Summary
                if let summary = log.conversationSummary {
                    detailSection("Conversation Summary") {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Response View
    
    private var responseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    
                    if let error = log.error {
                        DetailRow(label: "Error", value: error)
                            .foregroundStyle(.red)
                    }
                }
                
                // Headers
                if let headers = log.responseHeaders, !headers.isEmpty {
                    detailSection("Headers") {
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            DetailRow(label: key, value: value)
                        }
                    }
                }
                
                // Body
                if let bodyString = log.formattedResponseBody {
                    detailSection("Body") {
                        codeBlock(bodyString, copyValue: log.responseBodyString ?? bodyString)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - cURL View
    
    private var curlView: some View {
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
}

// MARK: - Detail Row

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