import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit
import CloudKit

// MARK: - Original ContentView with Logging Integration

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var input: String = ""
    @State private var showSettings: Bool = false
    @State private var showCalendar: Bool = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY") ?? ""
    @State private var errorMessage: String?
    @State private var isLoadingHealthData: Bool = false
    @State private var iCloudAvailable = false
    @State private var showMigrationAlert: Bool = false
    
    // Navigation state for deep linking
    @EnvironmentObject var navigationState: NavigationState

    private let model = "openai/gpt-5-mini" // GPT-5 via OpenRouter with 128k context window
    private let healthKitManager = HealthKitManager.shared
    
    // Load system prompt from file
    private var systemPrompt: String {
        SystemPromptLoader.loadSystemPromptWithSchedule()
    }
    
    // Computed properties for UI state
    private var messages: [ChatMessage] {
        conversationManager.messages
    }
    
    private var chatState: ChatState {
        conversationManager.conversationState.chatState
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
                ToolbarItem(placement: .topBarLeading) {
                    if iCloudAvailable {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showCalendar = true
                        } label: {
                            Image(systemName: "calendar")
                                .font(.body)
                        }
                        .accessibilityLabel("Training Calendar")
                        
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.body)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
        }
        .onAppear {
            // Initialize conversation manager
            Task {
                await conversationManager.initialize()
            }
            
            // Check iCloud availability
            CKContainer.default().accountStatus { status, _ in
                DispatchQueue.main.async {
                    iCloudAvailable = status == .available
                    if !iCloudAvailable {
                        print("⚠️ iCloud not available")
                    } else {
                        print("✅ iCloud is available")
                    }
                }
            }
            
            // Listen for iCloud changes
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                queue: .main
            ) { _ in
                print("📲 iCloud data changed")
                Task {
                    await conversationManager.loadConversation()
                }
            }
            
            // Listen for proactive messages
            NotificationCenter.default.addObserver(
                forName: Notification.Name("ProactiveMessageAdded"),
                object: nil,
                queue: .main
            ) { notification in
                print("🤖 Proactive message received")
                Task {
                    await conversationManager.loadConversation()
                }
            }
            
            // Request HealthKit authorization on app launch
            Task {
                if healthKitManager.isHealthKitAvailable {
                    do {
                        _ = try await healthKitManager.requestAuthorization()
                    } catch {
                        print("HealthKit authorization failed: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                apiKey: $apiKey,
                onClearChat: {
                    Task {
                        await conversationManager.clearConversation()
                    }
                },
                onSave: {
                    UserDefaults.standard.set(apiKey, forKey: "OPENROUTER_API_KEY")
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCalendar) {
            CalendarView()
                .environmentObject(navigationState)
        }
        .onChange(of: navigationState.showCalendar) { _, newValue in
            if newValue {
                showCalendar = true
                navigationState.showCalendar = false
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .alert("API Key Migration Required", isPresented: $showMigrationAlert, actions: {
            Button("Open Settings") {
                showSettings = true
            }
            Button("Later", role: .cancel) { }
        }, message: {
            Text("OpenRouter is now required for this app. Please update your API key in Settings. You can get an OpenRouter API key at openrouter.ai")
        })
        .onAppear {
            checkForMigration()
        }
    }
    
    // MARK: - Migration Helper
    
    private func checkForMigration() {
        // Check if user has old OpenAI key but no OpenRouter key
        let oldKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        let newKey = UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY")
        
        if let oldKey = oldKey, !oldKey.isEmpty, (newKey == nil || newKey!.isEmpty) {
            // User has old key but no new key - show migration alert
            showMigrationAlert = true
            
            // Clear the old key to avoid confusion
            UserDefaults.standard.removeObject(forKey: "OPENAI_API_KEY")
        }
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
                    
                    // Use the new unified status view
                    if chatState != .idle {
                        ChatStatusView(state: chatState)
                            .padding(.horizontal, 4)
                    }
                    
                    // Add invisible spacer at bottom to ensure last message isn't cut off
                    Color.clear
                        .frame(height: 20)
                        .id("bottom-spacer")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if chatState != .idle {
                        // When processing, scroll to show status indicator
                        proxy.scrollTo("status-indicator", anchor: .bottom)
                    } else {
                        // When idle, scroll to bottom spacer to ensure last message is fully visible
                        proxy.scrollTo("bottom-spacer", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatState) { _, _ in
                // Smooth scroll when state changes
                withAnimation(.easeOut(duration: 0.25)) {
                    if chatState != .idle {
                        proxy.scrollTo("status-indicator", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom when view appears
                if messages.count > 0 {
                    // Use DispatchQueue to ensure the scroll happens after the view is laid out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            // Scroll to the bottom spacer to ensure last message is fully visible
                            proxy.scrollTo("bottom-spacer", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        // Don't show system messages in the UI
        if message.role == .system {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            HStack {
                if message.role == .assistant {
                    Bubble(text: message.content, isUser: false)
                        .environmentObject(navigationState)
                    Spacer(minLength: 40)
                } else {
                    Spacer(minLength: 40)
                    Bubble(text: message.content, isUser: true)
                        .environmentObject(navigationState)
                }
            }
            .padding(.vertical, 2)
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(chatState != .idle)

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
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && conversationManager.conversationState == .idle
    }

    // MARK: - Actions

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Set your OpenRouter API key in Settings."
            return
        }
        
        input = ""
        
        do {
            try await conversationManager.sendMessage(
                text,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Components

private struct Bubble: View {
    let text: String
    let isUser: Bool
    @EnvironmentObject var navigationState: NavigationState
    @State private var showCalendar = false

    var body: some View {
        LinkDetectingText(text: text, isUser: isUser) { url in
            handleURL(url)
        }
        .font(.body)
        .foregroundStyle(isUser ? .white : .primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(isUser ? Color.blue : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sheet(isPresented: $showCalendar) {
            CalendarView()
                .environmentObject(navigationState)
        }
    }
    
    private func handleURL(_ url: URL) {
        print("🔗 Chat link tapped: \(url.absoluteString)")
        if url.scheme == "trainer" && url.host == "calendar" {
            // Extract the date from the path
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let dateString = pathComponents.first {
                print("🗓️ Deep link date string: \(dateString)")
                // Parse the date string
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                
                if let date = dateFormatter.date(from: dateString) {
                    print("✅ Parsed deep link date: \(date)")
                    navigationState.targetWorkoutDate = date
                    showCalendar = true
                } else {
                    print("❌ Failed to parse deep link date: \(dateString)")
                }
            } else {
                print("❌ No date component found in URL path components: \(url.pathComponents)")
            }
        } else {
            print("⚠️ Unsupported URL tapped: \(url.scheme ?? "nil")://\(url.host ?? "nil")\(url.path)")
        }
    }
}

// Custom view to detect and make links tappable
private struct LinkDetectingText: View {
    let text: String
    let isUser: Bool
    let onTap: (URL) -> Void
    
    var body: some View {
        let components = parseTextForLinks(text)
        
        if components.count == 1 && !components[0].isLink {
            // No links found, just show plain text
            Text(text)
        } else {
            // Build text with tappable links
            components.reduce(Text("")) { result, component in
                if component.isLink, let url = URL(string: component.text) {
                    // Build markdown with dynamic URL using AttributedString to avoid "%@" placeholder issue
                    let label = getLinkDisplayText(from: component.text)
                    let markdown = " [\(label)](\(url.absoluteString)) "
                    let attributed = (try? AttributedString(
                        markdown: markdown,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    )) ?? AttributedString(label)
                    
                    let linkText = Text(attributed)
                        .foregroundColor(isUser ? .white : .blue)
                        .underline()
                    
                    return result + linkText
                } else {
                    return result + Text(component.text)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                print("🔗 openURL action invoked with URL: \(url.absoluteString)")
                onTap(url)
                return .handled
            })
        }
    }
    
    private func getLinkDisplayText(from urlString: String) -> String {
        if urlString.starts(with: "trainer://calendar/") {
            return "📋 View instructions"
        }
        return "Link"
    }
    
    private func parseTextForLinks(_ text: String) -> [(text: String, isLink: Bool)] {
        var components: [(text: String, isLink: Bool)] = []
        
        // Pattern to match trainer:// URLs
        let pattern = #"trainer://[^\s]+"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var lastEndIndex = 0
            
            for match in matches {
                // Add text before the link
                if match.range.location > lastEndIndex {
                    let beforeText = nsString.substring(with: NSRange(location: lastEndIndex, length: match.range.location - lastEndIndex))
                    if !beforeText.isEmpty {
                        components.append((text: beforeText, isLink: false))
                    }
                }
                
                // Add the link
                let linkText = nsString.substring(with: match.range)
                components.append((text: linkText, isLink: true))
                
                lastEndIndex = match.range.location + match.range.length
            }
            
            // Add any remaining text after the last link
            if lastEndIndex < nsString.length {
                let remainingText = nsString.substring(from: lastEndIndex)
                if !remainingText.isEmpty {
                    components.append((text: remainingText, isLink: false))
                }
            }
            
        } catch {
            // If regex fails, just return the whole text as non-link
            components.append((text: text, isLink: false))
        }
        
        return components
    }
}

private struct SettingsSheet: View {
    @Binding var apiKey: String
    var onClearChat: () -> Void
    var onSave: () -> Void
    
    @State private var developerModeEnabled = UserDefaults.standard.bool(forKey: "DeveloperModeEnabled")
    @State private var apiLoggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    @State private var showDebugMenu = false
    @State private var showTimeControl = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter") {
                    SecureField("API Key (sk-or-...)", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Get your API key at [openrouter.ai](https://openrouter.ai)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Developer Options") {
                    Group {
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
                        
                        Button {
                            showTimeControl = true
                        } label: {
                            Label("Time Control", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                }
                
                Section {
                    Button(role: .destructive) {
                        onClearChat()
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                    
                    Button(role: .destructive) {
                        // Clear workout data without starting a new program
                        let manager = TrainingScheduleManager.shared
                        manager.currentProgram = nil
                        manager.currentBlock = nil
                        manager.workoutDays = []
                        
                        // Clear all workout data using TrainingScheduleManager's proper clear method
                        TrainingScheduleManager.shared.restartProgram()
                        
                        // Also clear any remaining workout keys using brute force approach
                        let userDefaults = UserDefaults.standard
                        let iCloudStore = NSUbiquitousKeyValueStore.default
                        
                        // Clear all keys starting with "workout_" from UserDefaults
                        let allKeys = userDefaults.dictionaryRepresentation().keys
                        for key in allKeys {
                            if key.hasPrefix("workout_") {
                                userDefaults.removeObject(forKey: key)
                                print("🧹 Cleared UserDefaults key: \(key)")
                            }
                        }
                        
                        // For iCloud, we'll rely on TrainingScheduleManager's clear method
                        // since NSUbiquitousKeyValueStore doesn't provide a way to list all keys
                        iCloudStore.synchronize()
                        
                        print("✅ All workout data cleared using comprehensive approach")
                    } label: {
                        Label("Clear Workout Data", systemImage: "calendar.badge.minus")
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
        .sheet(isPresented: $showTimeControl) {
            NavigationView {
                SimpleDeveloperTimeControl()
            }
            .presentationDetents([.large])
        }
    }
}

// MARK: - Models & Persistence


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
    /// API message structure for chat completions
    private struct APIMessage: Codable {
        let role: String
        let content: String
    }
    
    /// Create temporal-enhanced system prompt with current time context
    private static func createTemporalSystemPrompt(
        _ systemPrompt: String, 
        conversationHistory: [ChatMessage]
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        formatter.timeZone = TimeZone.current
        
        let currentTime = DateProvider.shared.currentDate
        let currentTimeString = formatter.string(from: currentTime)
        let sessionStartTime = conversationHistory.first?.date ?? currentTime
        let sessionStartString = formatter.string(from: sessionStartTime)
        
        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let durationMinutes = Int(sessionDuration / 60)
        
        let temporalContext = """
        
        [TEMPORAL_CONTEXT]
        Current time: \(currentTimeString)
        User timezone: \(TimeZone.current.identifier)
        Conversation started: \(sessionStartString)
        Session duration: \(durationMinutes) minutes
        """
        
        let enhancedPrompt = systemPrompt + temporalContext
        
        // Debug logging
        print("🕒 TEMPORAL_DEBUG: Enhanced system prompt with temporal context")
        print("🕒 Current time: \(currentTimeString)")
        print("🕒 Session duration: \(durationMinutes) minutes")
        print("🕒 Enhanced prompt length: \(enhancedPrompt.count) characters")
        
        return enhancedPrompt
    }
    /// Reusable DateFormatter for message timestamps to avoid allocation overhead
    private static let messageTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Format a message timestamp in a human-readable format with day of week
    private static func formatMessageTimestamp(_ date: Date) -> String {
        return messageTimestampFormatter.string(from: date)
    }
    
    /// Enhance a message with timestamp prefix for temporal context
    private static func enhanceMessageWithTimestamp(_ message: ChatMessage) -> APIMessage {
        let role: String
        switch message.role {
        case .user:
            role = "user"
        case .assistant:
            role = "assistant"
        case .system:
            role = "system"
        }
        
        // Only add timestamps to user and assistant messages
        // System messages should remain unmodified for tool results, etc.
        if message.role == .user || message.role == .assistant {
            let timestamp = formatMessageTimestamp(message.date)
            let enhancedContent = "[\(timestamp)]\n\(message.content)"
            return APIMessage(role: role, content: enhancedContent)
        } else {
            return APIMessage(role: role, content: message.content)
        }
    }
    
    
    static func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        struct RequestBody: Codable { let model: String; let messages: [APIMessage] }
        struct ResponseBody: Codable {
            struct Choice: Codable {
                struct Msg: Codable { let role: String; let content: String }
                let index: Int
                let message: Msg
            }
            let choices: [Choice]
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("com.yourcompany.TrainerApp", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120.0 // 2 minutes timeout for GPT-5 responses

        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let enhancedSystemPrompt = createTemporalSystemPrompt(systemPrompt, conversationHistory: history)
            msgs.append(APIMessage(role: "system", content: enhancedSystemPrompt))
            print("🕒 TEMPORAL_DEBUG: Using enhanced system prompt in complete() method")
        }
        
        // Add messages with timestamp enhancement
        for m in history {
            msgs.append(enhanceMessageWithTimestamp(m))
        }
        
        // Debug logging for timestamp enhancement
        print("📅 TEMPORAL_DEBUG: Enhanced \(history.count) messages with timestamps")
        if let firstMessage = history.first {
            let sample = formatMessageTimestamp(firstMessage.date)
            print("📅 Sample timestamp format: \(sample)")
        }

        let body = try JSONEncoder().encode(RequestBody(model: model, messages: msgs))
        request.httpBody = body

        // Log the request if enabled
        let startTime = Date()
        // Use EnhancedAPILogger with delegate-based streaming awareness
        let (data, resp) = try await URLSession.shared.enhancedLoggingDataTask(with: request)
        
        // Log the API call if logging is enabled
        if UserDefaults.standard.bool(forKey: "APILoggingEnabled") {
            APILogger.shared.log(
                request: request,
                response: resp,
                data: data,
                error: nil,
                startTime: startTime
            )
        }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.missingContent
        }
        return content
    }
    
    /// Streaming chat completion using SSE; streams tokens via onToken and returns the full text.
    static func streamComplete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        struct StreamRequestBody: Codable { let model: String; let messages: [APIMessage]; let stream: Bool }
        struct StreamDelta: Codable { let content: String? }
        struct StreamChoice: Codable { let delta: StreamDelta? }
        struct StreamChunk: Codable { let choices: [StreamChoice] }
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("com.yourcompany.TrainerApp", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120.0 // Keep consistent with non-streaming
        
        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let enhancedSystemPrompt = createTemporalSystemPrompt(systemPrompt, conversationHistory: history)
            msgs.append(APIMessage(role: "system", content: enhancedSystemPrompt))
            print("🕒 TEMPORAL_DEBUG: Using enhanced system prompt in streamComplete() method")
        }
        
        // Add messages with timestamp enhancement
        for m in history {
            msgs.append(enhanceMessageWithTimestamp(m))
        }
        
        // Debug logging for timestamp enhancement
        print("📅 TEMPORAL_DEBUG: Enhanced \(history.count) messages with timestamps")
        if let firstMessage = history.first {
            let sample = formatMessageTimestamp(firstMessage.date)
            print("📅 Sample timestamp format: \(sample)")
        }
        
        let reqBody = StreamRequestBody(model: model, messages: msgs, stream: true)
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        // Stream response lines
        let (bytes, resp, logId) = try await URLSession.shared.streamingLoggingDataTask(for: request)
        
        // If server returns an error status, consume the body to surface details, then throw
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorData = Data()
            // Accumulate any error payload (likely JSON) to help diagnose
            for try await chunk in bytes {
                errorData.append(contentsOf: [chunk])
            }
            if let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let err = (json["error"] as? [String: Any])?["message"] as? String {
                print("❌ Streaming error \(http.statusCode): \(err)")
            } else if let s = String(data: errorData, encoding: .utf8) {
                print("❌ Streaming error \(http.statusCode): \(s)")
            } else {
                print("❌ Streaming error \(http.statusCode): <no body>")
            }
            
            // Complete logging with error
            let errorMessage = (try? JSONSerialization.jsonObject(with: errorData) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: errorData, encoding: .utf8) ?? "<no body>"
            
            URLSession.shared.completeStreamingLog(
                id: logId,
                response: http,
                responseBody: errorMessage,
                error: LLMError.httpError(http.statusCode)
            )
            throw LLMError.httpError(http.statusCode)
        }
        
        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta?.content,
                  !delta.isEmpty else { continue }
            
            fullText += delta
            onToken(delta)
        }
        
        guard !fullText.isEmpty else {
            // Complete logging with error
            URLSession.shared.completeStreamingLog(
                id: logId,
                response: resp,
                responseBody: "",
                error: LLMError.missingContent
            )
            throw LLMError.missingContent
        }
        
        // Complete logging with successful response
        URLSession.shared.completeStreamingLog(
            id: logId,
            response: resp,
            responseBody: fullText,
            error: nil
        )
        
        return fullText
    }
}

// MARK: - API Logging Components removed (use centralized Logging/ implementations)


// MARK: - Preview

#Preview {
    ContentView()
}