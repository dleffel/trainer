import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit

// MARK: - Original ContentView with Logging Integration

struct ContentView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var showSettings: Bool = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var errorMessage: String?
    @State private var isLoadingHealthData: Bool = false

    private let persistence = ConversationPersistence()
    private let model = "gpt-5" // GPT-5 with 128k context window
    private let healthKitManager = HealthKitManager.shared
    
    // Load system prompt from file
    private var systemPrompt: String {
        loadSystemPromptFromFile()
    }
    
    private func loadSystemPromptFromFile() -> String {
        // First, try Bundle (for when file is added to Xcode project)
        if let bundleURL = Bundle.main.url(forResource: "SystemPrompt", withExtension: "md") {
            do {
                let content = try String(contentsOf: bundleURL, encoding: .utf8)
                print("✅ Loaded SystemPrompt.md from Bundle")
                return content
            } catch {
                print("❌ Error loading from Bundle: \(error)")
            }
        }
        
        // Try multiple possible paths for development
        let fileManager = FileManager.default
        let possiblePaths = [
            // Absolute path
            "/Users/danielleffel/repos/trainer/TrainerApp/TrainerApp/SystemPrompt.md",
            // Relative to current directory
            "\(fileManager.currentDirectoryPath)/TrainerApp/TrainerApp/SystemPrompt.md",
            "TrainerApp/TrainerApp/SystemPrompt.md",
            // Just in case we're in TrainerApp directory
            "TrainerApp/SystemPrompt.md"
        ]
        
        print("📁 Current directory: \(fileManager.currentDirectoryPath)")
        print("🔍 Searching for SystemPrompt.md in paths:")
        
        for path in possiblePaths {
            print("  - \(path)")
            if fileManager.fileExists(atPath: path) {
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    print("✅ Loaded SystemPrompt.md from: \(path)")
                    // Verify we got the rowing coach content
                    if content.contains("Rowing‑Coach GPT") {
                        print("✅ Verified: Found rowing coach content!")
                        return content
                    } else {
                        print("⚠️ Warning: File found but doesn't contain expected content")
                    }
                } catch {
                    print("❌ Error loading from \(path): \(error)")
                }
            }
        }
        
        // FATAL: Cannot load system prompt - this is an irrecoverable error
        fatalError("❌ FATAL ERROR: SystemPrompt.md not found! The app cannot function without the system prompt file.")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesList
                inputBar
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .onAppear {
            messages = (try? persistence.load()) ?? []
            // TODO: Uncomment when files are added to project
            // Request HealthKit authorization on app launch
            // Task {
            //     if healthKitManager.isHealthKitAvailable {
            //         do {
            //             _ = try await healthKitManager.requestAuthorization()
            //         } catch {
            //             print("HealthKit authorization failed: \(error)")
            //         }
            //     }
            // }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                apiKey: $apiKey,
                onClearChat: {
                    messages.removeAll()
                    try? persistence.clear()
                },
                onSave: {
                    UserDefaults.standard.set(apiKey, forKey: "OPENAI_API_KEY")
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Views

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { msg in
                        bubble(for: msg)
                            .id(msg.id)
                    }
                    if isSending {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if isSending {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else if let last = messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                Bubble(text: message.content, isUser: false)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Bubble(text: message.content, isUser: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var typingIndicator: some View {
        HStack {
            ShimmerDot()
            ShimmerDot(delay: 0.2)
            ShimmerDot(delay: 0.4)
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(isSending)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(canSend ? Color.blue : Color.gray)
            }
            .disabled(!canSend)
        }
        .padding(.all, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Actions

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Set your OpenAI API key in Settings."
            return
        }

        input = ""
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        persist()

        isSending = true
        do {
            let assistantText = try await LLMClient.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: messages
            )
            
            // Process any tool calls in the response
            let toolProcessor = ToolProcessor.shared
            let processedText = try await toolProcessor.processResponse(assistantText)
            
            let assistantMsg = ChatMessage(role: .assistant, content: processedText)
            messages.append(assistantMsg)
            persist()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    private func persist() {
        do { try persistence.save(messages) }
        catch { print("Persist error: \(error)") }
    }
}

// MARK: - Components

private struct Bubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isUser ? .white : .primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isUser ? Color.blue : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct ShimmerDot: View {
    @State private var on = false
    var delay: Double = 0.0

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 8, height: 8)
            .opacity(on ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever().delay(delay), value: on)
            .onAppear { on = true }
    }
}

private struct SettingsSheet: View {
    @Binding var apiKey: String
    var onClearChat: () -> Void
    var onSave: () -> Void
    
    @State private var developerModeEnabled = UserDefaults.standard.bool(forKey: "DeveloperModeEnabled")
    @State private var apiLoggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    @State private var showDebugMenu = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section("Developer Options") {
                    Toggle("Developer Mode", isOn: $developerModeEnabled)
                        .onChange(of: developerModeEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "DeveloperModeEnabled")
                            if !newValue {
                                // Disable API logging when developer mode is turned off
                                apiLoggingEnabled = false
                                UserDefaults.standard.set(false, forKey: "APILoggingEnabled")
                            }
                        }
                    
                    if developerModeEnabled {
                        Toggle("API Logging", isOn: $apiLoggingEnabled)
                            .onChange(of: apiLoggingEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "APILoggingEnabled")
                                APILogger.shared.setLoggingEnabled(newValue)
                            }
                        
                        Button {
                            showDebugMenu = true
                        } label: {
                            Label("View API Logs", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(!apiLoggingEnabled)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        onClearChat()
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave() }
                }
            }
        }
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView()
                .presentationDetents([.large])
        }
    }
}

// MARK: - Models & Persistence

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let date: Date

    init(id: UUID = UUID(), role: Role, content: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
    }

    enum Role: String, Codable {
        case user, assistant
    }
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
}

private struct ConversationPersistence {
    private var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("conversation.json")
    }

    func load() throws -> [ChatMessage] {
        let data = try Data(contentsOf: url)
        let stored = try JSONDecoder().decode([StoredMessage].self, from: data)
        return stored.compactMap { s in
            guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
            return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
        }
    }

    func save(_ messages: [ChatMessage]) throws {
        let stored = messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, date: m.date)
        }
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: [.atomic])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - LLM Client

enum LLMError: LocalizedError {
    case missingContent
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingContent: return "No content returned by the model."
        case .invalidResponse: return "Unexpected response from the model."
        case .httpError(let code): return "Network error: HTTP \(code)."
        }
    }
}

enum LLMClient {
    static func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        struct APIMessage: Codable { let role: String; let content: String }
        struct RequestBody: Codable { let model: String; let messages: [APIMessage] }
        struct ResponseBody: Codable {
            struct Choice: Codable {
                struct Msg: Codable { let role: String; let content: String }
                let index: Int
                let message: Msg
            }
            let choices: [Choice]
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msgs.append(APIMessage(role: "system", content: systemPrompt))
        }
        for m in history {
            msgs.append(APIMessage(role: m.role == .user ? "user" : "assistant", content: m.content))
        }

        let body = try JSONEncoder().encode(RequestBody(model: model, messages: msgs))
        request.httpBody = body

        // Use logging session if API logging is enabled
        let session = UserDefaults.standard.bool(forKey: "APILoggingEnabled") ? URLSession.shared : URLSession.shared
        let (data, resp) = try await session.loggedData(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.missingContent
        }
        return content
    }
}

// MARK: - API Logging Components

/// Token usage information from API response
struct TokenUsage: Codable {
    let totalTokens: Int
    let promptTokens: Int
    let completionTokens: Int
    let model: String?
    
    var contextPercentage: Double {
        // Get context window size based on model
        let contextWindow = getContextWindowSize()
        return Double(totalTokens) / Double(contextWindow) * 100.0
    }
    
    private func getContextWindowSize() -> Int {
        // Context windows for different models
        // GPT-5 is assumed to have 128k+ tokens like GPT-4 Turbo
        guard let model = model else { return 128000 }
        
        switch model.lowercased() {
        case let m where m.contains("gpt-5"):
            return 128000  // 128k tokens for GPT-5
        case let m where m.contains("gpt-4-turbo"), let m where m.contains("gpt-4-1106"):
            return 128000  // 128k tokens
        case let m where m.contains("gpt-4-32k"):
            return 32768   // 32k tokens
        case let m where m.contains("gpt-4"):
            return 8192    // 8k tokens
        case let m where m.contains("gpt-3.5-turbo-16k"):
            return 16384   // 16k tokens
        case let m where m.contains("gpt-3.5"):
            return 4096    // 4k tokens
        default:
            return 128000  // Default to 128k for unknown/future models
        }
    }
}

/// Represents a single API request/response log entry
struct APILogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let requestURL: String
    let requestMethod: String
    let requestHeaders: [String: String]
    let requestBody: Data?
    let responseStatusCode: Int?
    let responseHeaders: [String: String]?
    let responseBody: Data?
    let duration: TimeInterval
    let error: String?
    let apiKeyPreview: String // Last 4 chars only for security
    let tokenUsage: TokenUsage?
    
    var requestBodyString: String? {
        guard let data = requestBody else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: prettyData, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8)
    }
    
    var responseBodyString: String? {
        guard let data = responseBody else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: prettyData, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8)
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        requestURL: String,
        requestMethod: String,
        requestHeaders: [String: String],
        requestBody: Data?,
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: Data? = nil,
        duration: TimeInterval = 0,
        error: String? = nil,
        apiKeyPreview: String = "",
        tokenUsage: TokenUsage? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.requestURL = requestURL
        self.requestMethod = requestMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
        self.error = error
        self.apiKeyPreview = apiKeyPreview
        self.tokenUsage = tokenUsage
    }
    
    var isSuccess: Bool {
        guard let statusCode = responseStatusCode else { return false }
        return (200...299).contains(statusCode)
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var formattedDuration: String {
        return String(format: "%.3fs", duration)
    }
    
    var curlCommand: String {
        var components = ["curl"]
        components.append("-X \(requestMethod)")
        
        for (key, value) in requestHeaders {
            if key.lowercased() == "authorization" {
                let maskedValue = maskAuthorizationValue(value)
                components.append("-H '\(key): \(maskedValue)'")
            } else {
                components.append("-H '\(key): \(value)'")
            }
        }
        
        if let bodyString = requestBodyString {
            let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\"'\"'")
            components.append("-d '\(escapedBody)'")
        }
        
        components.append("'\(requestURL)'")
        return components.joined(separator: " \\\n  ")
    }
    
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
}

/// Singleton class responsible for logging API requests and responses
final class APILogger {
    static let shared = APILogger()
    
    private let persistence = LoggingPersistence()
    private let queue = DispatchQueue(label: "com.trainerapp.apilogger", qos: .background)
    private var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    }
    
    private init() {}
    
    func log(request: URLRequest, response: URLResponse?, data: Data?, error: Error?, startTime: Date) {
        guard isLoggingEnabled else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        queue.async { [weak self] in
            let logEntry = self?.createLogEntry(
                request: request,
                response: response,
                data: data,
                error: error,
                duration: duration
            )
            
            if let entry = logEntry {
                self?.persistence.append(entry)
            }
        }
    }
    
    private func createLogEntry(
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        error: Error?,
        duration: TimeInterval
    ) -> APILogEntry {
        let requestURL = request.url?.absoluteString ?? "Unknown"
        let requestMethod = request.httpMethod ?? "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody
        
        let apiKeyPreview = extractAPIKeyPreview(from: requestHeaders)
        
        var responseStatusCode: Int?
        var responseHeaders: [String: String]?
        
        if let httpResponse = response as? HTTPURLResponse {
            responseStatusCode = httpResponse.statusCode
            responseHeaders = httpResponse.allHeaderFields as? [String: String]
        }
        
        let errorMessage = error?.localizedDescription
        
        // Extract token usage from response if available
        var tokenUsage: TokenUsage?
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = json["usage"] as? [String: Any],
           let totalTokens = usage["total_tokens"] as? Int,
           let promptTokens = usage["prompt_tokens"] as? Int,
           let completionTokens = usage["completion_tokens"] as? Int {
            
            // Extract model name from response if available
            let modelName = json["model"] as? String
            
            tokenUsage = TokenUsage(
                totalTokens: totalTokens,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                model: modelName
            )
        }
        
        return APILogEntry(
            requestURL: requestURL,
            requestMethod: requestMethod,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: responseStatusCode,
            responseHeaders: responseHeaders,
            responseBody: data,
            duration: duration,
            error: errorMessage,
            apiKeyPreview: apiKeyPreview,
            tokenUsage: tokenUsage
        )
    }
    
    private func extractAPIKeyPreview(from headers: [String: String]) -> String {
        guard let authHeader = headers["Authorization"] else { return "" }
        
        if authHeader.hasPrefix("Bearer ") {
            let token = String(authHeader.dropFirst(7))
            if token.count >= 4 {
                return String(token.suffix(4))
            }
        }
        
        return ""
    }
    
    func getAllLogs() -> [APILogEntry] {
        return persistence.loadAll()
    }
    
    func clearAllLogs() {
        queue.async { [weak self] in
            self?.persistence.clearAll()
        }
    }
    
    func setLoggingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "APILoggingEnabled")
    }
    
    func getStorageInfo() -> (logCount: Int, oldestLog: Date?, newestLog: Date?) {
        let logs = getAllLogs()
        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        
        return (
            logCount: logs.count,
            oldestLog: sorted.first?.timestamp,
            newestLog: sorted.last?.timestamp
        )
    }
}

/// Handles persistence of API logs to JSON files
final class LoggingPersistence {
    private let maxLogsPerFile = 1000
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.trainerapp.logging.persistence", qos: .background)
    
    private var logsDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logsDir = documentsDirectory.appendingPathComponent("APILogs")
        
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir
    }
    
    private var activeLogFileURL: URL {
        logsDirectory.appendingPathComponent("api_logs.json")
    }
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func append(_ logEntry: APILogEntry) {
        queue.sync {
            var logs = loadLogsFromFile(activeLogFileURL)
            logs.append(logEntry)
            
            if logs.count >= maxLogsPerFile {
                archiveCurrentLogs(logs)
                logs = [logEntry]
            }
            
            saveLogsToFile(logs, url: activeLogFileURL)
        }
    }
    
    func loadAll() -> [APILogEntry] {
        var allLogs: [APILogEntry] = []
        allLogs.append(contentsOf: loadLogsFromFile(activeLogFileURL))
        
        if let archivedFiles = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ) {
            let archiveFiles = archivedFiles.filter { url in
                url.lastPathComponent.hasPrefix("api_logs_") &&
                url.lastPathComponent.hasSuffix(".json") &&
                url.lastPathComponent != "api_logs.json"
            }
            
            for archiveFile in archiveFiles.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                allLogs.append(contentsOf: loadLogsFromFile(archiveFile))
            }
        }
        
        return allLogs
    }
    
    func clearAll() {
        queue.sync {
            if let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    private func loadLogsFromFile(_ url: URL) -> [APILogEntry] {
        guard let data = try? Data(contentsOf: url),
              let logs = try? decoder.decode([APILogEntry].self, from: data) else {
            return []
        }
        return logs
    }
    
    private func saveLogsToFile(_ logs: [APILogEntry], url: URL) {
        guard let data = try? encoder.encode(logs) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    private func archiveCurrentLogs(_ logs: [APILogEntry]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        
        let archiveURL = logsDirectory.appendingPathComponent("api_logs_\(dateString).json")
        saveLogsToFile(logs, url: archiveURL)
    }
}

// MARK: - URLSession Extension

extension URLSession {
    func loggedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let startTime = Date()
        
        do {
            let (data, response) = try await self.data(for: request)
            
            APILogger.shared.log(
                request: request,
                response: response,
                data: data,
                error: nil,
                startTime: startTime
            )
            
            return (data, response)
        } catch {
            APILogger.shared.log(
                request: request,
                response: nil,
                data: nil,
                error: error,
                startTime: startTime
            )
            
            throw error
        }
    }
}

// MARK: - Debug Menu View

struct DebugMenuView: View {
    @State private var logs: [APILogEntry] = []
    @State private var filteredLogs: [APILogEntry] = []
    @State private var searchText = ""
    @State private var selectedLog: APILogEntry?
    
    var body: some View {
        NavigationStack {
            VStack {
                searchBar
                
                if filteredLogs.isEmpty {
                    emptyState
                } else {
                    logsList
                }
            }
            .navigationTitle("API Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All") {
                        APILogger.shared.clearAllLogs()
                        loadLogs()
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
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search URLs or response content", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, _ in
                    applyFilters()
                }
        }
        .padding()
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
            
            Text("No API requests have been logged yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func loadLogs() {
        logs = APILogger.shared.getAllLogs()
        applyFilters()
    }
    
    private func applyFilters() {
        var filtered = logs
        
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter { log in
                log.requestURL.lowercased().contains(searchLower) ||
                log.responseBodyString?.lowercased().contains(searchLower) ?? false
            }
        }
        
        filtered.sort { $0.timestamp > $1.timestamp }
        filteredLogs = filtered
    }
}

struct APILogRowView: View {
    let log: APILogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(log.requestMethod)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Text(log.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(log.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(formatURL(log.requestURL))
                .font(.footnote)
                .lineLimit(1)
            
            HStack {
                if let statusCode = log.responseStatusCode {
                    Text("HTTP \(statusCode)")
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
                
                if let usage = log.tokenUsage {
                    Spacer()
                    
                    // Token usage display
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(usage.totalTokens) tokens")
                                .font(.caption2)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 4) {
                                Text("↑\(usage.promptTokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                
                                Text("↓\(usage.completionTokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        // Context usage indicator
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 8)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(contextUsageColor(for: usage.contextPercentage))
                                .frame(width: 60 * min(usage.contextPercentage / 100.0, 1.0), height: 8)
                        }
                        
                        Text("\(Int(usage.contextPercentage))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(contextUsageColor(for: usage.contextPercentage))
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func contextUsageColor(for percentage: Double) -> Color {
        switch percentage {
        case 0..<50:
            return .green
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
    
    private var statusColor: Color {
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
        return url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "api.openai.com/", with: "")
    }
}

struct APILogDetailView: View {
    let log: APILogEntry
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Token Usage Summary
                if let usage = log.tokenUsage {
                    detailSection("Token Usage") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Total Tokens", systemImage: "sum")
                                    .font(.footnote)
                                Spacer()
                                Text("\(usage.totalTokens)")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Label("Prompt Tokens", systemImage: "arrow.up.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("\(usage.promptTokens)")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Label("Completion Tokens", systemImage: "arrow.down.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                                Spacer()
                                Text("\(usage.completionTokens)")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                            }
                            
                            Divider()
                            
                            HStack {
                                Label("Context Usage", systemImage: "chart.bar.fill")
                                    .font(.footnote)
                                Spacer()
                                
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 100, height: 12)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(contextUsageColor(for: usage.contextPercentage))
                                        .frame(width: 100 * min(usage.contextPercentage / 100.0, 1.0), height: 12)
                                }
                                
                                Text("\(Int(usage.contextPercentage))%")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(contextUsageColor(for: usage.contextPercentage))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                
                detailSection("Request") {
                    Text("URL: \(log.requestURL)")
                        .font(.footnote)
                    Text("Method: \(log.requestMethod)")
                        .font(.footnote)
                    
                    if let body = log.requestBodyString {
                        Text("Body:")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        Text(body)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                detailSection("Response") {
                    if let statusCode = log.responseStatusCode {
                        Text("Status: \(statusCode)")
                            .font(.footnote)
                    }
                    
                    Text("Duration: \(log.formattedDuration)")
                        .font(.footnote)
                    
                    if let body = log.responseBodyString {
                        Text("Body:")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        ScrollView(.horizontal) {
                            Text(body)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                
                detailSection("cURL") {
                    Text(log.curlCommand)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding()
        }
        .navigationTitle("Log Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func contextUsageColor(for percentage: Double) -> Color {
        switch percentage {
        case 0..<50:
            return .green
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}