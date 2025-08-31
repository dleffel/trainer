import Foundation
import UserNotifications
import BackgroundTasks
import SwiftUI

/// Manages proactive messaging by periodically waking the LLM coach to evaluate context
class ProactiveCoachManager: NSObject {
    static let shared = ProactiveCoachManager()
    
    // Configuration
    private let backgroundTaskIdentifier = "com.trainerapp.coachCheck"
    
    // State tracking
    private var lastMessageTime: Date?
    private var todaysMessageCount = 0
    private var lastAppOpenTime: Date?
    
    // Dependencies
    private let notificationCenter = UNUserNotificationCenter.current()
    private let healthKitManager = HealthKitManager.shared
    private let scheduleManager = TrainingScheduleManager.shared
    private let persistence = ConversationPersistence()
    
    // Settings from UserDefaults
    private var settings: ProactiveMessagingSettings {
        var settings = ProactiveMessagingSettings()
        
        let defaults = UserDefaults.standard
        
        // Check if enabled has been explicitly set, otherwise default to true
        if defaults.object(forKey: "proactiveMessagingEnabled") != nil {
            settings.enabled = defaults.bool(forKey: "proactiveMessagingEnabled")
        } else {
            // First time - set default to true
            settings.enabled = true
            defaults.set(true, forKey: "proactiveMessagingEnabled")
        }
        
        settings.checkFrequency = TimeInterval(defaults.integer(forKey: "proactiveCheckInterval") * 60)
        settings.maxMessagesPerDay = defaults.integer(forKey: "proactiveMaxMessagesPerDay")
        
        // Set defaults if not yet configured
        if settings.checkFrequency == 0 {
            settings.checkFrequency = 30 * 60 // 30 minutes default
            defaults.set(30, forKey: "proactiveCheckInterval")
        }
        if settings.maxMessagesPerDay == 0 {
            settings.maxMessagesPerDay = 3
            defaults.set(3, forKey: "proactiveMaxMessagesPerDay")
        }
        
        // Quiet hours
        if defaults.bool(forKey: "proactiveQuietHoursEnabled") {
            let start = defaults.integer(forKey: "proactiveQuietHoursStart")
            let end = defaults.integer(forKey: "proactiveQuietHoursEnd")
            // Don't create a range if it would be invalid (e.g., 22...6)
            // We'll handle the logic in shouldSuppressCheck instead
            settings.quietHoursStart = start
            settings.quietHoursEnd = end
        }
        
        // Sunday review
        settings.sundayReviewEnabled = defaults.bool(forKey: "proactiveSundayReviewEnabled")
        let reviewHour = defaults.integer(forKey: "proactiveSundayReviewHour")
        settings.sundayReviewTime = DateComponents(hour: reviewHour == 0 ? 19 : reviewHour, minute: 0)
        
        return settings
    }
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
        resetDailyMessageCount()
    }
    
    // MARK: - Public Interface
    
    /// Request notification permissions and start proactive monitoring
    func initialize() async -> Bool {
        print("🚀 ProactiveCoachManager: Starting initialization...")
        
        // Check if enabled
        if !settings.enabled {
            print("⚠️ ProactiveCoachManager: Smart reminders are disabled in settings")
            return false
        }
        
        // Request notification permissions
        do {
            print("📱 ProactiveCoachManager: Requesting notification permissions...")
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            
            print("📱 ProactiveCoachManager: Permissions granted: \(granted)")
            
            if granted {
                await setupNotificationCategories()
                registerBackgroundTask()
                scheduleNextCheck()
                print("✅ ProactiveCoachManager: Initialized successfully")
                print("   ↳ Check interval: \(Int(settings.checkFrequency/60)) minutes")
                print("   ↳ Max messages/day: \(settings.maxMessagesPerDay)")
                if let start = settings.quietHoursStart, let end = settings.quietHoursEnd {
                    print("   ↳ Quiet hours: \(start):00 - \(end):00")
                }
            } else {
                print("❌ ProactiveCoachManager: Notification permissions denied")
            }
            
            return granted
        } catch {
            print("❌ ProactiveCoachManager: Failed to request permissions: \(error)")
            return false
        }
    }
    
    /// Record that the app was opened (affects message suppression)
    func recordAppOpen() {
        lastAppOpenTime = Date()
    }
    
    /// Manually trigger a context evaluation (for testing)
    func triggerEvaluation() async {
        await evaluateAndAct(isTest: true)
    }
    
    // MARK: - Context Gathering
    
    private func gatherCurrentContext() async -> CoachContext {
        let now = Date()
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: now)
        let dayName = DateFormatter().weekdaySymbols[dayOfWeek - 1]
        
        // Check if program exists
        let programExists = scheduleManager.programStartDate != nil
        
        // Get today's workout info
        let todaysWorkout = scheduleManager.currentWeekDays.first { workoutDay in
            calendar.isDate(workoutDay.date, inSameDayAs: now)
        }
        
        // Get health data
        let healthData = try? await healthKitManager.fetchHealthData()
        let hasHealthData = healthData != nil && (healthData?.weight != nil || healthData?.age != nil)
        
        // Calculate days since last message
        let daysSinceLastMessage: Int? = {
            guard let lastMessage = lastMessageTime else { return nil }
            return calendar.dateComponents([.day], from: lastMessage, to: now).day
        }()
        
        return CoachContext(
            currentTime: now,
            dayOfWeek: dayName,
            lastMessageTime: lastMessageTime,
            todaysWorkout: todaysWorkout?.plannedWorkout,
            workoutCompleted: todaysWorkout?.completed ?? false,
            lastWorkoutTime: findLastWorkoutTime(),
            currentBlock: programExists ? (scheduleManager.currentBlock?.type.rawValue ?? "Unknown") : "No program",
            weekNumber: scheduleManager.totalWeekInProgram,
            recentMetrics: healthData != nil ? HealthMetrics(
                weight: healthData?.weight,
                bodyFat: healthData?.bodyFatPercentage,
                sleep: healthData?.timeAsleepHours
            ) : nil,
            programExists: programExists,
            hasHealthData: hasHealthData,
            messagesSentToday: todaysMessageCount,
            daysSinceLastMessage: daysSinceLastMessage
        )
    }
    
    private func findLastWorkoutTime() -> Date? {
        // Find the most recent completed workout from current week
        return scheduleManager.currentWeekDays
            .filter { $0.completed }
            .sorted { $0.date > $1.date }
            .first?
            .date
    }
    
    // MARK: - LLM Decision Making
    
    private func evaluateAndAct(isTest: Bool = false) async {
        // Check suppression rules first (unless this is a test)
        let context = await gatherCurrentContext()
        
        if !isTest && shouldSuppressCheck(context: context) {
            print("🔇 ProactiveCoachManager: Suppressing check due to rules")
            return
        }
        
        if isTest {
            print("🧪 ProactiveCoachManager: Test mode - bypassing suppression rules")
        }
        
        // Ask the coach what to do
        let decision = await askCoachWhatToDo(context: context)
        
        // Log the decision for debugging
        logCoachDecision(context: context, decision: decision)
        
        // Act on the decision
        if decision.shouldSendMessage, let message = decision.message {
            await sendProactiveMessage(message)
            lastMessageTime = Date()
            todaysMessageCount += 1
        }
    }
    
    private func askCoachWhatToDo(context: CoachContext) async -> CoachDecision {
        print("🤔 ProactiveCoachManager: Starting enhanced evaluation...")
        
        // Get the API key
        guard let apiKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"),
              !apiKey.isEmpty else {
            print("❌ ProactiveCoachManager: No API key configured")
            return CoachDecision(
                shouldSendMessage: true,
                message: "Ready to start your rowing journey? Open the app to add your API key and begin!",
                reasoning: "No API key configured - guiding user to complete setup"
            )
        }
        
        // Build enhanced prompt with full system context
        let systemPrompt = buildEnhancedSystemPrompt()
        let contextPrompt = context.contextPrompt
        
        // Initial LLM call
        let initialPrompt = """
        \(contextPrompt)
        
        CRITICAL INSTRUCTIONS:
        1. You MUST use [TOOL_CALL: get_training_status] first
        2. If it returns "No program started", you MUST call BOTH:
           - [TOOL_CALL: start_training_program]
           - [TOOL_CALL: plan_week]
        3. ONLY claim to have initialized a program if you actually called these tools
        
        Include ALL necessary tool calls in your response, then provide your decision.
        """
        
        do {
            print("📤 ProactiveCoachManager: Initial LLM call...")
            var response = try await LLMClient.complete(
                apiKey: apiKey,
                model: "gpt-5",
                systemPrompt: systemPrompt,
                history: [ChatMessage(role: .user, content: initialPrompt)]
            )
            
            print("📥 ProactiveCoachManager: Initial response received")
            
            // Process any tool calls
            let (finalResponse, toolResults) = await processProactiveToolCalls(response)
            
            // If tools were executed, make a follow-up call with results
            if !toolResults.isEmpty {
                print("🔧 ProactiveCoachManager: Tools executed, making follow-up call...")
                
                let toolResultsFormatted = formatToolResults(toolResults)
                
                // Check if we need to initialize the program
                let needsInitialization = toolResults.contains { result in
                    result.toolName == "get_training_status" &&
                    result.result.contains("No program started")
                }
                
                let followUpPrompt: String
                if needsInitialization {
                    followUpPrompt = """
                    The tool results show NO PROGRAM EXISTS:
                    \(toolResultsFormatted)
                    
                    You MUST now execute these initialization tools:
                    [TOOL_CALL: start_training_program]
                    [TOOL_CALL: plan_week]
                    
                    DO NOT send a message claiming you initialized anything yet.
                    Include the tool calls above in your response.
                    """
                } else {
                    followUpPrompt = """
                    Based on the tool results:
                    \(toolResultsFormatted)
                    
                    Now provide your final decision:
                    SEND: [Yes/No]
                    REASONING: [One sentence explaining why]
                    MESSAGE: [If Yes, the exact message to send to the athlete]
                    """
                }
                
                response = try await LLMClient.complete(
                    apiKey: apiKey,
                    model: "gpt-5",
                    systemPrompt: systemPrompt,
                    history: [
                        ChatMessage(role: .assistant, content: finalResponse),
                        ChatMessage(role: .user, content: followUpPrompt)
                    ]
                )
                
                print("📥 ProactiveCoachManager: Final response received")
            }
            
            return parseCoachDecision(response)
            
        } catch {
            print("❌ ProactiveCoachManager: LLM call failed: \(error)")
            return CoachDecision(
                shouldSendMessage: false,
                message: nil,
                reasoning: "LLM call failed: \(error)"
            )
        }
    }
    
    // MARK: - Enhanced System Prompt
    
    private func buildEnhancedSystemPrompt() -> String {
        // Load the full rowing coach system prompt
        let systemPrompt = SystemPromptLoader.loadSystemPrompt()
        
        return """
        \(systemPrompt)
        
        ## PROACTIVE MESSAGING MODE
        
        You are evaluating whether to send a proactive message to your athlete.
        This is a background check - the athlete hasn't opened the app.
        
        ### CRITICAL RULE: NEVER LIE ABOUT ACTIONS
        
        **ABSOLUTELY FORBIDDEN**: Claiming to have done something without actually doing it.
        - NEVER say "I've initialized your program" without calling [TOOL_CALL: start_training_program]
        - NEVER say "I've planned your week" without calling [TOOL_CALL: plan_week]
        - NEVER make claims about actions that haven't been executed via tools
        
        ### REQUIRED TOOL EXECUTION FLOW:
        
        1. ALWAYS start with [TOOL_CALL: get_training_status]
        
        2. If status shows "No program started":
           You MUST execute these tools IN ORDER:
           - [TOOL_CALL: start_training_program]
           - [TOOL_CALL: plan_week]
           
           Your response MUST include ALL these tool calls like:
           ```
           [TOOL_CALL: get_training_status]
           [TOOL_CALL: start_training_program]
           [TOOL_CALL: plan_week]
           
           SEND: Yes
           REASONING: Program needed initialization
           MESSAGE: I've set up your 20-week training program...
           ```
        
        3. If program already exists:
           - Use other tools as needed for context
           - Craft appropriate message based on current state
        
        ### AVAILABLE TOOLS:
        - [TOOL_CALL: get_training_status] - ALWAYS use first
        - [TOOL_CALL: start_training_program] - REQUIRED if no program
        - [TOOL_CALL: plan_week] - REQUIRED after starting program
        - [TOOL_CALL: get_health_data] - Optional for context
        - [TOOL_CALL: get_weekly_schedule] - Optional for existing programs
        
        ### VERIFICATION:
        Before sending any message claiming an action was taken:
        1. Check that the corresponding tool was called
        2. Only claim success if the tool executed successfully
        3. Base your message on actual tool results, not assumptions
        """
    }
    
    // MARK: - Tool Processing
    
    private func processProactiveToolCalls(_ response: String) async -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult]) {
        do {
            let processed = try await ToolProcessor.shared.processResponseWithToolCalls(response)
            
            if processed.requiresFollowUp {
                print("🔧 ProactiveCoachManager: Executed \(processed.toolResults.count) tools")
                for result in processed.toolResults {
                    print("   ↳ \(result.toolName): \(result.success ? "✅" : "❌")")
                }
            }
            
            return (processed.cleanedResponse, processed.toolResults)
        } catch {
            print("❌ ProactiveCoachManager: Tool processing failed: \(error)")
            return (response, [])
        }
    }
    
    private func formatToolResults(_ results: [ToolProcessor.ToolCallResult]) -> String {
        return results.map { result in
            if result.success {
                return "[\(result.toolName) result]:\n\(result.result)"
            } else {
                return "[\(result.toolName) failed]: \(result.error ?? "Unknown error")"
            }
        }.joined(separator: "\n\n")
    }
    
    private func parseCoachDecision(_ response: String) -> CoachDecision {
        let lines = response.split(separator: "\n", omittingEmptySubsequences: false)
        var shouldSend = false
        var reasoning = ""
        var message: String?
        var isCapturingMessage = false
        var messageLines: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if we're in message capture mode
            if isCapturingMessage {
                // Stop capturing if we hit another field marker
                if trimmed.hasPrefix("SEND:") || trimmed.hasPrefix("REASONING:") {
                    isCapturingMessage = false
                } else {
                    // Add this line to the message
                    messageLines.append(String(line))
                }
            }
            
            if trimmed.hasPrefix("SEND:") {
                let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                shouldSend = value.lowercased() == "yes"
                isCapturingMessage = false
            } else if trimmed.hasPrefix("REASONING:") {
                reasoning = String(trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces))
                isCapturingMessage = false
            } else if trimmed.hasPrefix("MESSAGE:") {
                // Get what's after MESSAGE: on the same line
                let sameLineContent = String(trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces))
                if !sameLineContent.isEmpty {
                    messageLines.append(sameLineContent)
                }
                // Start capturing subsequent lines
                isCapturingMessage = true
            }
        }
        
        // Join message lines if we captured any
        if !messageLines.isEmpty {
            message = messageLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Don't send empty messages
            if message?.isEmpty == true {
                message = nil
            }
        }
        
        // Debug logging
        print("🔍 ParseCoachDecision Debug:")
        print("   Response length: \(response.count)")
        print("   Should send: \(shouldSend)")
        print("   Reasoning: \(reasoning)")
        print("   Message: \(message ?? "nil")")
        print("   Message lines captured: \(messageLines.count)")
        
        return CoachDecision(
            shouldSendMessage: shouldSend,
            message: message,
            reasoning: reasoning
        )
    }
    
    // MARK: - Notification Handling
    
    private func sendProactiveMessage(_ message: String) async {
        // First, add the message to the chat conversation
        await addMessageToConversation(message)
        
        // Then send the notification
        let content = UNMutableNotificationContent()
        content.title = "Your Rowing Coach"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "COACH_MESSAGE"
        
        // Add metadata
        content.userInfo = [
            "type": "proactive_coach",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await notificationCenter.add(request)
            print("📬 ProactiveCoachManager: Sent message: \(message)")
        } catch {
            print("❌ ProactiveCoachManager: Failed to send notification: \(error)")
        }
    }
    
    private func addMessageToConversation(_ message: String) async {
        await MainActor.run {
            // Load existing messages
            var messages = (try? persistence.load()) ?? []
            
            // Add the proactive message from the assistant
            let assistantMessage = ChatMessage(role: .assistant, content: message)
            messages.append(assistantMessage)
            
            // Save the updated conversation
            try? persistence.save(messages)
            
            print("💬 ProactiveCoachManager: Added message to conversation")
            
            // Post notification to update UI if it's open
            NotificationCenter.default.post(
                name: Notification.Name("ProactiveMessageAdded"),
                object: nil,
                userInfo: ["message": assistantMessage]
            )
        }
    }
    
    private func setupNotificationCategories() async {
        let openAppAction = UNNotificationAction(
            identifier: "OPEN_APP",
            title: "Open App",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "COACH_MESSAGE",
            actions: [openAppAction, dismissAction],
            intentIdentifiers: []
        )
        
        notificationCenter.setNotificationCategories([category])
    }
    
    // MARK: - Background Task Management
    
    private func registerBackgroundTask() {
        // Note: This is now handled in AppDelegate to avoid launch timing issues
        print("📱 ProactiveCoachManager: Background task handler registered in AppDelegate")
    }
    
    /// Handle background refresh from AppDelegate
    func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        handleBackgroundTask(task)
    }
    
    private func scheduleNextCheck() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: settings.checkFrequency)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 ProactiveCoachManager: Scheduled next check in \(Int(settings.checkFrequency/60)) minutes")
        } catch {
            print("❌ ProactiveCoachManager: Failed to schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await evaluateAndAct(isTest: false)
            scheduleNextCheck()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Suppression Logic
    
    private func shouldSuppressCheck(context: CoachContext) -> Bool {
        // Check if proactive messaging is enabled
        if !settings.enabled {
            print("   ↳ Proactive messaging is disabled")
            return true
        }
        
        // Check quiet hours
        if settings.quietHoursStart != nil && settings.quietHoursEnd != nil {
            let hour = Calendar.current.component(.hour, from: context.currentTime)
            let start = settings.quietHoursStart!
            let end = settings.quietHoursEnd!
            
            // Handle ranges that cross midnight
            if start > end {
                // e.g., 22 (10 PM) to 6 (6 AM)
                if hour >= start || hour < end {
                    print("   ↳ In quiet hours (\(start):00 - \(end):00)")
                    return true
                }
            } else {
                // Normal range (e.g., 9 to 17)
                if hour >= start && hour < end {
                    print("   ↳ In quiet hours (\(start):00 - \(end):00)")
                    return true
                }
            }
        }
        
        // Check daily message limit
        if todaysMessageCount >= settings.maxMessagesPerDay {
            print("   ↳ Daily message limit reached (\(todaysMessageCount)/\(settings.maxMessagesPerDay))")
            return true
        }
        
        // Check if app was recently opened
        if let lastOpen = lastAppOpenTime,
           context.currentTime.timeIntervalSince(lastOpen) < 15 * 60 {
            let minutesAgo = Int(context.currentTime.timeIntervalSince(lastOpen) / 60)
            print("   ↳ App opened \(minutesAgo) minutes ago (< 15 min threshold)")
            return true
        }
        
        // Check if we sent a message recently
        if let lastMessage = lastMessageTime,
           context.currentTime.timeIntervalSince(lastMessage) < settings.minimumMessageInterval {
            let minutesAgo = Int(context.currentTime.timeIntervalSince(lastMessage) / 60)
            let threshold = Int(settings.minimumMessageInterval / 60)
            print("   ↳ Last message sent \(minutesAgo) minutes ago (< \(threshold) min threshold)")
            return true
        }
        
        return false
    }
    
    // MARK: - Helpers
    
    private func resetDailyMessageCount() {
        // Reset count at midnight
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let midnight = calendar.startOfDay(for: tomorrow)
        
        let timer = Timer(fireAt: midnight, interval: 0, target: self, selector: #selector(dailyReset), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
    }
    
    @objc private func dailyReset() {
        todaysMessageCount = 0
        resetDailyMessageCount()
    }
    
    private func logCoachDecision(context: CoachContext, decision: CoachDecision) {
        print("🤖 ProactiveCoachManager Decision:")
        print("   Time: \(formatTime(context.currentTime))")
        print("   Send: \(decision.shouldSendMessage ? "Yes" : "No")")
        print("   Reasoning: \(decision.reasoning)")
        if let message = decision.message {
            print("   Message: \(message)")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Conversation Persistence (copied from ContentView)

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
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
}

// MARK: - Supporting Types

struct CoachContext {
    let currentTime: Date
    let dayOfWeek: String
    let lastMessageTime: Date?
    let todaysWorkout: String?
    let workoutCompleted: Bool
    let lastWorkoutTime: Date?
    let currentBlock: String
    let weekNumber: Int
    let recentMetrics: HealthMetrics?
    
    // New setup-related fields
    let programExists: Bool
    let hasHealthData: Bool
    let messagesSentToday: Int
    let daysSinceLastMessage: Int?
    
    var contextPrompt: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let currentTimeStr = timeFormatter.string(from: currentTime)
        
        var prompt = """
        CURRENT CONTEXT:
        - Time: \(currentTimeStr) on \(dayOfWeek)
        """
        
        if programExists {
            prompt += """
            
            - Training: Week \(weekNumber) of \(currentBlock) block
            - Today's workout: \(todaysWorkout ?? "Rest day")
            - Workout completed: \(workoutCompleted ? "Yes" : "No")
            """
        } else {
            prompt += """
            
            - Training: No active training program
            - Status: New athlete, needs program initialization
            """
        }
        
        // Add last message timing
        if let lastMessage = lastMessageTime {
            let hoursSince = currentTime.timeIntervalSince(lastMessage) / 3600
            prompt += "\n- Last message sent: \(Int(hoursSince)) hours ago"
        } else {
            prompt += "\n- Last message sent: Never"
        }
        
        // Add workout history
        if let lastWorkout = lastWorkoutTime {
            let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout, to: currentTime).day ?? 0
            prompt += "\n- Last workout: \(daysSince) days ago"
        }
        
        // Add health data status
        prompt += "\n- Health data: \(hasHealthData ? "Available" : "Not available")"
        
        if let metrics = recentMetrics {
            if let weight = metrics.weight {
                prompt += "\n- Current weight: \(String(format: "%.1f", weight)) lbs"
            }
        }
        
        prompt += "\n\nBased on this context, check setup state if needed, then decide on messaging."
        
        return prompt
    }
}

struct CoachDecision {
    let shouldSendMessage: Bool
    let message: String?
    let reasoning: String
}

struct HealthMetrics {
    let weight: Double?
    let bodyFat: Double?
    let sleep: Double?
}

struct ProactiveMessagingSettings {
    var enabled: Bool = true
    var checkFrequency: TimeInterval = 30 * 60 // 30 minutes
    var quietHoursStart: Int? = 22 // 10 PM
    var quietHoursEnd: Int? = 6 // 6 AM
    var maxMessagesPerDay: Int = 3
    var minimumMessageInterval: TimeInterval = 60 * 60 // 1 hour between messages
    var sundayReviewEnabled: Bool = true
    var sundayReviewTime: DateComponents = DateComponents(hour: 19, minute: 0) // 7 PM
}

// MARK: - UNUserNotificationCenterDelegate

extension ProactiveCoachManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "OPEN_APP", UNNotificationDefaultActionIdentifier:
            // User tapped the notification - app will open
            recordAppOpen()
        case "DISMISS":
            // User dismissed - no action needed
            break
        default:
            break
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}