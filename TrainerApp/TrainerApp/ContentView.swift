import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit
import CloudKit

// MARK: - Original ContentView with Logging Integration

struct ContentView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var showSettings: Bool = false
    @State private var showCalendar: Bool = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var errorMessage: String?
    @State private var isLoadingHealthData: Bool = false
    @State private var isProcessingTools: Bool = false
    @State private var iCloudAvailable = false
    
    // Navigation state for deep linking
    @EnvironmentObject var navigationState: NavigationState

    private let persistence = ConversationPersistence()
    private let model = "gpt-5" // GPT-5 with 128k context window
    private let healthKitManager = HealthKitManager.shared
    private let maxConversationTurns = 5 // Maximum turns for tool processing
    
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
            messages = (try? persistence.load()) ?? []
            
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
                messages = (try? persistence.load()) ?? messages
            }
            
            // Listen for proactive messages
            NotificationCenter.default.addObserver(
                forName: Notification.Name("ProactiveMessageAdded"),
                object: nil,
                queue: .main
            ) { notification in
                print("🤖 Proactive message received")
                // Reload messages to include the new proactive message
                messages = (try? persistence.load()) ?? messages
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
                    messages.removeAll()
                    try? persistence.clear()
                },
                onSave: {
                    UserDefaults.standard.set(apiKey, forKey: "OPENAI_API_KEY")
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
                        if isProcessingTools {
                            processingToolsIndicator
                                .id("processing")
                        } else {
                            typingIndicator
                                .id("typing")
                        }
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
                    if isSending {
                        // When sending, scroll to show indicators properly
                        if isProcessingTools {
                            proxy.scrollTo("processing", anchor: .bottom)
                        } else {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    } else {
                        // When not sending, scroll to bottom spacer to ensure last message is fully visible
                        proxy.scrollTo("bottom-spacer", anchor: .bottom)
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
    
    private var processingToolsIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isProcessingTools ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isProcessingTools)
            
            Text("Checking health data...")
                .font(.footnote)
                .foregroundColor(.secondary)
            
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
        isProcessingTools = false
        
        do {
            // Create a working copy of messages for the conversation
            var conversationHistory = messages
            var finalResponse = ""
            var turns = 0
            
            repeat {
                turns += 1
                
                // Get AI response
                let assistantText = try await LLMClient.complete(
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    history: conversationHistory
                )
                
                // Process any tool calls in the response
                let toolProcessor = ToolProcessor.shared
                let processedResponse = try await toolProcessor.processResponseWithToolCalls(assistantText)
                
                if processedResponse.requiresFollowUp && !processedResponse.toolResults.isEmpty {
                    isProcessingTools = true
                    
                    // Add the cleaned assistant response if it has content
                    if !processedResponse.cleanedResponse.isEmpty {
                        conversationHistory.append(
                            ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                        )
                    }
                    
                    // Format and add tool results as a system message
                    let toolResultsMessage = toolProcessor.formatToolResults(processedResponse.toolResults)
                    conversationHistory.append(
                        ChatMessage(role: .system, content: toolResultsMessage)
                    )
                    
                    // Continue the loop to get AI's response to the tool results
                } else {
                    // No tool calls, this is the final response
                    finalResponse = processedResponse.cleanedResponse
                    break
                }
                
            } while turns < maxConversationTurns
            
            // Add the final assistant message to the visible conversation
            let assistantMsg = ChatMessage(role: .assistant, content: finalResponse)
            messages.append(assistantMsg)
            persist()
            
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        
        isSending = false
        isProcessingTools = false
    }

    private func persist() {
        do {
            try persistence.save(messages)
            print("💾 Persist called with \(messages.count) messages")
        }
        catch {
            print("❌ Persist error: \(error)")
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
        if url.scheme == "trainer" && url.host == "calendar" {
            // Extract the date from the path
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let dateString = pathComponents.first {
                // Parse the date string
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                
                if let date = dateFormatter.date(from: dateString) {
                    navigationState.targetWorkoutDate = date
                    showCalendar = true
                }
            }
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
                    return result + Text(" [\(getLinkDisplayText(from: component.text))](\(component.text)) ")
                        .foregroundColor(isUser ? .white : .blue)
                        .underline()
                } else {
                    return result + Text(component.text)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
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
    @State private var showProactiveSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section("Smart Reminders") {
                    Button {
                        showProactiveSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Configure Smart Reminders")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
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
                    
                    Button(role: .destructive) {
                        // Clear workout data without starting a new program
                        let manager = TrainingScheduleManager.shared
                        manager.currentProgram = nil
                        manager.currentBlock = nil
                        manager.workoutDays = []
                        
                        // Clear from UserDefaults and iCloud
                        let userDefaults = UserDefaults.standard
                        let iCloudStore = NSUbiquitousKeyValueStore.default
                        
                        // Clear program key
                        userDefaults.removeObject(forKey: "TrainingProgram")
                        iCloudStore.removeObject(forKey: "TrainingProgram")
                        
                        // Clear workout completion keys for a reasonable date range
                        let calendar = Calendar.current
                        for dayOffset in -365...365 {
                            if let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                let dateKey = formatter.string(from: date)
                                let workoutKey = "workout_\(dateKey)"
                                
                                userDefaults.removeObject(forKey: workoutKey)
                                iCloudStore.removeObject(forKey: workoutKey)
                            }
                        }
                        
                        iCloudStore.synchronize()
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
        .sheet(isPresented: $showProactiveSettings) {
            ProactiveMessagingSettingsView()
                .presentationDetents([.medium, .large])
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
        case user, assistant, system
    }
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
}

private struct ConversationPersistence {
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private let conversationKey = "trainer_conversations"
    
    // Local backup URL
    private var localURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("conversation.json")
    }
    
    init() {
        // Synchronize with iCloud to get latest data
        let synchronized = keyValueStore.synchronize()
        print("🔄 iCloud synchronize on init: \(synchronized)")
    }
    
    func load() throws -> [ChatMessage] {
        // Try iCloud first
        if let data = keyValueStore.data(forKey: conversationKey) {
            let messages = try JSONDecoder().decode([StoredMessage].self, from: data)
            print("✅ Loaded from iCloud")
            return messages.compactMap { s in
                guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
            }
        }
        
        // Fallback to local
        if FileManager.default.fileExists(atPath: localURL.path) {
            let data = try Data(contentsOf: localURL)
            let stored = try JSONDecoder().decode([StoredMessage].self, from: data)
            print("📱 Loaded from local storage")
            return stored.compactMap { s in
                guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
            }
        }
        
        return []
    }
    
    func save(_ messages: [ChatMessage]) throws {
        let stored = messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, date: m.date)
        }
        let data = try JSONEncoder().encode(stored)
        
        // Save to both local and iCloud
        try data.write(to: localURL, options: [.atomic])
        
        // Save to iCloud (1MB limit)
        if data.count < 1_000_000 {
            keyValueStore.set(data, forKey: conversationKey)
            let synced = keyValueStore.synchronize()
            print("☁️ Saved to iCloud (\(data.count) bytes) - Sync started: \(synced)")
            
            // Verify the save
            if let savedData = keyValueStore.data(forKey: conversationKey) {
                print("✅ Verified: Data exists in iCloud store (\(savedData.count) bytes)")
            } else {
                print("⚠️ Warning: Data not found in iCloud store after save")
            }
        } else {
            print("⚠️ Data too large for iCloud key-value store (\(data.count) bytes)")
        }
    }
    
    func clear() throws {
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        keyValueStore.removeObject(forKey: conversationKey)
        keyValueStore.synchronize()
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
        request.timeoutInterval = 120.0 // 2 minutes timeout for GPT-5 responses

        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msgs.append(APIMessage(role: "system", content: systemPrompt))
        }
        for m in history {
            let role = switch m.role {
                case .user: "user"
                case .assistant: "assistant"
                case .system: "system"
            }
            msgs.append(APIMessage(role: role, content: m.content))
        }

        let body = try JSONEncoder().encode(RequestBody(model: model, messages: msgs))
        request.httpBody = body

        // Log the request if enabled
        let startTime = Date()
        let (data, resp) = try await URLSession.shared.data(for: request)
        
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


// MARK: - Preview

#Preview {
    ContentView()
}