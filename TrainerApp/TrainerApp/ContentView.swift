import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit
import CloudKit

// MARK: - Original ContentView with Logging Integration

struct ContentView: View {
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var chatState: ChatState = .idle  // New single state variable
    @State private var showSettings: Bool = false
    @State private var showCalendar: Bool = false
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY") ?? ""
    @State private var errorMessage: String?
    @State private var isLoadingHealthData: Bool = false
    @State private var iCloudAvailable = false
    @State private var showMigrationAlert: Bool = false
    
    // Navigation state for deep linking
    @EnvironmentObject var navigationState: NavigationState

    private let persistence = ConversationPersistence()
    private let model = "openai/gpt-5" // GPT-5 via OpenRouter with 128k context window
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
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatState == .idle
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
        
        // Update state with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            chatState = .preparingResponse
        }
        
        do {
            // Create a working copy of messages for the conversation
            var conversationHistory = messages
            var finalResponse = ""
            var turns = 0
            
            // Prepare a placeholder assistant message for streaming
            var assistantIndex: Int? = nil
            
            repeat {
                turns += 1
                
                if turns == 1 {
                    // STREAMING: Start in streaming state, but don't create message yet
                    await MainActor.run {
                        // Just transition to streaming state - no message creation yet
                        withAnimation(.easeInOut(duration: 0.3)) {
                            chatState = .streaming(progress: nil)
                        }
                    }
                    
                    let requestStart = Date()
                    print("⏱️ request_start: \(requestStart.timeIntervalSince1970)")
                    
                    var streamedFullText = ""
                    var tokenBuffer = ""
                    var isBufferingTool = false
                    var messageCreated = false
                    let assistantText: String
                    do {
                        assistantText = try await LLMClient.streamComplete(
                            apiKey: apiKey,
                            model: model,
                            systemPrompt: systemPrompt,
                            history: conversationHistory,
                            onToken: { token in
                                // Buffer tokens to detect tool patterns early
                                tokenBuffer.append(token)
                                
                                // Check for tool pattern in buffer
                                if tokenBuffer.contains("[TOOL_CALL:") && !isBufferingTool {
                                    isBufferingTool = true
                                    // Extract tool name for specific feedback
                                    if tokenBuffer.range(of: #"\[TOOL_CALL:\s*(\w+)"#, options: .regularExpression) != nil {
                                        // Extract tool name for specific feedback
                                        if let colonRange = tokenBuffer.range(of: ":"),
                                           let toolNameStart = tokenBuffer.index(colonRange.upperBound, offsetBy: 1, limitedBy: tokenBuffer.endIndex) {
                                            let toolNameEnd = tokenBuffer.firstIndex(of: "(") ?? tokenBuffer.firstIndex(of: "]") ?? tokenBuffer.endIndex
                                            let toolName = String(tokenBuffer[toolNameStart..<toolNameEnd]).trimmingCharacters(in: .whitespaces)
                                        
                                            Task { @MainActor in
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    chatState = .toolState(for: toolName)
                                                }
                                            }
                                        }
                                    }
                                } else if !isBufferingTool {
                                    // Only append non-tool content to visible message
                                    streamedFullText.append(token)
                                    Task { @MainActor in
                                        // Create message on first content token
                                        if !messageCreated && !streamedFullText.isEmpty {
                                            let newMessage = ChatMessage(role: .assistant, content: streamedFullText)
                                            messages.append(newMessage)
                                            assistantIndex = messages.count - 1
                                            messageCreated = true
                                        } else if let idx = assistantIndex {
                                            // Update existing message
                                            messages[idx] = ChatMessage(role: .assistant, content: streamedFullText)
                                        }
                                    }
                                }
                                
                                // Keep full text for processing
                                if isBufferingTool {
                                    streamedFullText = tokenBuffer
                                }
                            }
                        )
                    } catch {
                        // Fallback to non-streaming on invalid request/model/other 4xx
                        print("⚠️ Streaming failed: \(error). Falling back to non-streaming.")
                        let fallbackText = try await LLMClient.complete(
                            apiKey: apiKey,
                            model: model,
                            systemPrompt: systemPrompt,
                            history: conversationHistory
                        )
                        // Ensure user sees a response even without streaming
                        await MainActor.run {
                            if let idx = assistantIndex {
                                messages[idx] = ChatMessage(role: .assistant, content: fallbackText)
                            } else {
                                messages.append(ChatMessage(role: .assistant, content: fallbackText))
                                assistantIndex = messages.count - 1
                            }
                        }
                        streamedFullText = fallbackText
                        assistantText = fallbackText
                    }
                    
                    print("⏱️ response_complete (streamed): \(Date().timeIntervalSince1970)")
                    
                    // Process any tool calls in the streamed response
                    let toolProcessor = ToolProcessor.shared
                    let processedResponse = try await toolProcessor.processResponseWithToolCalls(assistantText)
                    
                    if processedResponse.requiresFollowUp && !processedResponse.toolResults.isEmpty {
                        print("⏱️ tools_start: \(Date().timeIntervalSince1970)")
                        
                        // Update state to show tool processing with specific feedback
                        for result in processedResponse.toolResults {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    chatState = .toolState(for: result.toolName)
                                }
                            }
                            // Brief pause to show each tool
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                        
                        // Add the cleaned assistant response if it has content
                        if !processedResponse.cleanedResponse.isEmpty {
                            conversationHistory.append(
                                ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                            )
                            // Update visible bubble to cleaned response (remove any tool tags)
                            await MainActor.run {
                                if let idx = assistantIndex {
                                    messages[idx] = ChatMessage(role: .assistant, content: processedResponse.cleanedResponse)
                                }
                            }
                        }
                        
                        // Format and add tool results as a system message
                        let toolResultsMessage = toolProcessor.formatToolResults(processedResponse.toolResults)
                        conversationHistory.append(
                            ChatMessage(role: .system, content: toolResultsMessage)
                        )
                        
                        print("⏱️ tools_complete: \(Date().timeIntervalSince1970)")
                        // Continue the loop to get AI's response to the tool results (non-streaming for now)
                    } else {
                        // No tool calls, this is the final response
                        finalResponse = processedResponse.cleanedResponse
                        // Ensure the visible bubble matches final response
                        await MainActor.run {
                            if let idx = assistantIndex {
                                messages[idx] = ChatMessage(role: .assistant, content: finalResponse)
                            }
                            
                            // Transition to finalizing
                            withAnimation(.easeInOut(duration: 0.3)) {
                                chatState = .finalizing
                            }
                        }
                        break
                    }
                } else {
                    // FOLLOW-UP: Use non-streaming completion
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            chatState = .preparingResponse
                        }
                    }
                    
                    let assistantText = try await LLMClient.complete(
                        apiKey: apiKey,
                        model: model,
                        systemPrompt: systemPrompt,
                        history: conversationHistory
                    )
                    
                    let toolProcessor = ToolProcessor.shared
                    let processedResponse = try await toolProcessor.processResponseWithToolCalls(assistantText)
                    
                    finalResponse = processedResponse.cleanedResponse
                    await MainActor.run {
                        if let idx = assistantIndex {
                            messages[idx] = ChatMessage(role: .assistant, content: finalResponse)
                        } else {
                            // Fallback: append if no streaming bubble present
                            messages.append(ChatMessage(role: .assistant, content: finalResponse))
                        }
                        
                        // Transition to finalizing
                        withAnimation(.easeInOut(duration: 0.3)) {
                            chatState = .finalizing
                        }
                    }
                    break
                }
                
            } while turns < maxConversationTurns
            
            persist()
            
            // Brief pause before returning to idle
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    chatState = .idle
                }
            }
            
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    chatState = .idle
                }
            }
        }
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
        .sheet(isPresented: $showTimeControl) {
            NavigationView {
                SimpleDeveloperTimeControl()
            }
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
        struct APIMessage: Codable { let role: String; let content: String }
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
        
        let reqBody = StreamRequestBody(model: model, messages: msgs, stream: true)
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        // Stream response lines
        let (bytes, resp) = try await URLSession.shared.bytes(for: request)
        
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
        
        guard !fullText.isEmpty else { throw LLMError.missingContent }
        return fullText
    }
}

// MARK: - API Logging Components removed (use centralized Logging/ implementations)


// MARK: - Preview

#Preview {
    ContentView()
}