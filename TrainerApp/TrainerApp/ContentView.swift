import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit
import CloudKit

// MARK: - Main App View with Tab Navigation

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var showSettings: Bool = false
    @State private var errorMessage: String?
    @State private var iCloudAvailable = false
    @State private var showMigrationAlert: Bool = false
    
    // Navigation state for deep linking and tab selection
    @EnvironmentObject var navigationState: NavigationState

    private let healthKitManager = HealthKitManager.shared
    private let config = AppConfiguration.shared

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            ChatTab(
                conversationManager: conversationManager,
                showSettings: $showSettings,
                iCloudAvailable: iCloudAvailable
            )
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(0)
            
            LogTab(showSettings: $showSettings)
                .tabItem {
                    Label("Log", systemImage: "calendar")
                }
                .tag(1)
        }
        .onAppear {
            Task {
                await conversationManager.initialize()
            }
            checkForMigration()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                onClearChat: {
                    Task {
                        await conversationManager.clearConversation()
                    }
                }
            )
            .presentationDetents([.medium, .large])
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
    }
    
    // MARK: - Setup & Helpers
    
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
}

// MARK: - Chat Tab

private struct ChatTab: View {
    @ObservedObject var conversationManager: ConversationManager
    @Binding var showSettings: Bool
    let iCloudAvailable: Bool
    
    @EnvironmentObject var navigationState: NavigationState
    @State private var input: String = ""
    @State private var errorMessage: String?
    
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
                    Bubble(
                        messageId: message.id,
                        text: message.content,
                        reasoning: message.reasoning,
                        isUser: false,
                        conversationManager: conversationManager
                    )
                    .environmentObject(navigationState)
                    Spacer(minLength: 40)
                } else {
                    Spacer(minLength: 40)
                    Bubble(
                        messageId: message.id,
                        text: message.content,
                        reasoning: nil,
                        isUser: true,
                        conversationManager: conversationManager
                    )
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
        
        input = ""
        
        do {
            try await conversationManager.sendMessage(text)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Log Tab

private struct LogTab: View {
    @Binding var showSettings: Bool
    @EnvironmentObject var navigationState: NavigationState
    
    var body: some View {
        NavigationStack {
            CalendarContentView()
                .navigationTitle("Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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
}

// MARK: - Calendar Content View (extracted from CalendarView)

private struct CalendarContentView: View {
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @EnvironmentObject var navigationState: NavigationState
    @State private var navigatedToWorkout = false
    
    var body: some View {
        VStack(spacing: 0) {
            WeeklyCalendarView(scheduleManager: scheduleManager)
            Spacer()
        }
        .onAppear {
            // Handle deep link navigation
            if let targetDate = navigationState.targetWorkoutDate, !navigatedToWorkout {
                print("🧭 LogTab detected deep link target: \(targetDate)")
                navigatedToWorkout = true
                // Pass navigation handling to WeeklyCalendarView
                print("🧭 LogTab passing navigation to WeeklyCalendarView via navigationState")
            }
        }
    }
}

// MARK: - Components

private struct Bubble: View {
    let messageId: UUID
    let text: String
    let reasoning: String?
    let isUser: Bool
    @ObservedObject var conversationManager: ConversationManager
    
    @EnvironmentObject var navigationState: NavigationState
    
    // Computed property - is THIS message currently streaming reasoning?
    private var isStreamingReasoning: Bool {
        let isLastMessage = conversationManager.messages.last?.id == messageId
        return isLastMessage && conversationManager.isStreamingReasoning
    }
    
    // Computed property - get latest reasoning chunk only if this message is streaming
    private var latestReasoningChunk: String? {
        isStreamingReasoning ? conversationManager.latestReasoningChunk : nil
    }
    @State private var showReasoning = false
    @State private var previewLines: [String] = []
    @State private var lastReasoningLength: Int = 0
    @AppStorage("ShowAIReasoning") private var showReasoningSetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show reasoning section if available and enabled
            if let reasoning = reasoning, !reasoning.isEmpty, showReasoningSetting {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showReasoning.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.caption)
                        Text("Coach's Thinking")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: showReasoning ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Preview scroll view when collapsed and streaming
                if !showReasoning && isStreamingReasoning && !previewLines.isEmpty {
                    VStack(spacing: 2) {
                        Divider()
                            .padding(.horizontal, -14)
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundColor(.secondary.opacity(0.8))
                                            .italic()
                                            .id(index)
                                    }
                                }
                            }
                            .frame(height: 60)
                            .onChange(of: previewLines.count) { _, _ in
                                // Scroll to bottom when new lines arrive
                                if let lastIndex = previewLines.indices.last {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(lastIndex, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 4)
                        
                        Divider()
                            .padding(.horizontal, -14)
                    }
                }
                
                if showReasoning {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.leading, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Divider()
                    .padding(.vertical, 4)
            }
            
            // Main message content
            LinkDetectingText(text: text, isUser: isUser) { url in
                handleURL(url)
            }
            .font(.body)
        }
        .foregroundStyle(isUser ? .white : .primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(isUser ? Color.blue : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onChange(of: conversationManager.isStreamingReasoning) { _, newValue in
            // Only process if this is the last message
            let isLastMessage = conversationManager.messages.last?.id == messageId
            guard isLastMessage else { return }
            
            if !newValue {
                // Streaming stopped, clear preview after a brief moment
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(.easeOut(duration: 0.3)) {
                        previewLines = []
                    }
                }
            }
        }
        .onChange(of: conversationManager.latestReasoningChunk) { _, _ in
            // Only update if this is the last message and we're streaming
            let isLastMessage = conversationManager.messages.last?.id == messageId
            guard isLastMessage && conversationManager.isStreamingReasoning else { return }
            guard !showReasoning && showReasoningSetting else { return }
            
            updatePreviewLines()
        }
    }
    
    @MainActor
    private func updatePreviewLines() {
        // Get the actual message's current reasoning, not the snapshot
        guard let message = conversationManager.messages.first(where: { $0.id == messageId }),
              let fullReasoning = message.reasoning, !fullReasoning.isEmpty else {
            previewLines = []
            lastReasoningLength = 0
            return
        }
        
        // Only update if we've accumulated at least 50 more characters since last update
        // This prevents rapid jank as individual words arrive
        guard fullReasoning.count >= lastReasoningLength + 50 else { return }
        
        // Split into lines and take the last 5
        let allLines = fullReasoning.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Show last 5 lines
        previewLines = Array(allLines.suffix(5))
        lastReasoningLength = fullReasoning.count
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
                    // Set target date first, then switch tab with slight delay
                    // This ensures WeeklyCalendarView receives the target date
                    navigationState.targetWorkoutDate = date
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationState.selectedTab = 1
                    }
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
    var onClearChat: () -> Void
    
    private let config = AppConfiguration.shared
    @State private var apiKey: String = AppConfiguration.shared.apiKey
    @State private var developerModeEnabled = UserDefaults.standard.bool(forKey: "DeveloperModeEnabled")
    @State private var apiLoggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    @AppStorage("ShowAIReasoning") private var showAIReasoning = false
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
                Section("AI Features") {
                    Toggle("Show AI Reasoning", isOn: $showAIReasoning)
                    Text("Display the coach's internal reasoning process when planning workouts (requires GPT-5 or other reasoning models)")
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
                    Button("Save") {
                        config.apiKey = apiKey
                    }
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


// MARK: - Preview

#Preview {
    ContentView()
}