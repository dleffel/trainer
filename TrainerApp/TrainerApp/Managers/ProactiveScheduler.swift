import Foundation
import BackgroundTasks

/// Protocol for scheduler abstraction
protocol ProactiveSchedulerProtocol {
    func initialize() async -> Bool
    func triggerEvaluation() async
    func recordAppOpen()
}

/// Manages proactive check scheduling, rate limiting, and suppression rules
class ProactiveScheduler: ProactiveSchedulerProtocol {
    
    // MARK: - Configuration
    private let backgroundTaskIdentifier = "com.trainerapp.coachCheck"
    
    // MARK: - State tracking
    private var lastMessageTime: Date?
    private var todaysMessageCount = 0
    private var lastAppOpenTime: Date?
    
    // MARK: - Dependencies
    private let coachBrain: CoachBrainProtocol
    private let messageDelivery: MessageDeliveryProtocol
    private let healthKitManager = HealthKitManager.shared
    private let scheduleManager = TrainingScheduleManager.shared
    
    // MARK: - Settings from UserDefaults
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
            settings.quietHoursStart = start
            settings.quietHoursEnd = end
        }
        
        // Sunday review
        settings.sundayReviewEnabled = defaults.bool(forKey: "proactiveSundayReviewEnabled")
        let reviewHour = defaults.integer(forKey: "proactiveSundayReviewHour")
        settings.sundayReviewTime = DateComponents(hour: reviewHour == 0 ? 19 : reviewHour, minute: 0)
        
        return settings
    }
    
    // MARK: - Initialization
    init(coachBrain: CoachBrainProtocol? = nil, messageDelivery: MessageDeliveryProtocol? = nil) {
        self.coachBrain = coachBrain ?? CoachBrain()
        self.messageDelivery = messageDelivery ?? MessageDeliveryService()
        
        setupNotificationObservers()
        resetDailyMessageCount()
    }
    
    // MARK: - Public Interface
    
    /// Initialize the scheduler and request permissions
    func initialize() async -> Bool {
        print("🚀 ProactiveScheduler: Starting initialization...")
        
        // Check if enabled
        if !settings.enabled {
            print("⚠️ ProactiveScheduler: Smart reminders are disabled in settings")
            return false
        }
        
        // Request notification permissions
        do {
            let granted = try await messageDelivery.requestNotificationPermissions()
            
            if granted {
                await messageDelivery.setupNotificationCategories()
                registerBackgroundTask()
                scheduleNextCheck()
                print("✅ ProactiveScheduler: Initialized successfully")
                logConfiguration()
            } else {
                print("❌ ProactiveScheduler: Notification permissions denied")
            }
            
            return granted
        } catch {
            print("❌ ProactiveScheduler: Initialization failed: \(error)")
            return false
        }
    }
    
    /// Record that the app was opened (affects message suppression)
    func recordAppOpen() {
        lastAppOpenTime = Date()
        print("📱 ProactiveScheduler: App opened, resetting timer")
    }
    
    /// Manually trigger a context evaluation (for testing)
    func triggerEvaluation() async {
        print("🧪 ProactiveScheduler: Manual evaluation triggered")
        await evaluateAndAct(isTest: true)
    }
    
    // MARK: - Core Logic
    
    private func evaluateAndAct(isTest: Bool = false) async {
        // Gather context
        let context = await gatherCurrentContext()
        
        // Check suppression rules first (unless this is a test)
        if !isTest && shouldSuppressCheck(context: context) {
            print("🔇 ProactiveScheduler: Suppressing check due to rules")
            return
        }
        
        if isTest {
            print("🧪 ProactiveScheduler: Test mode - bypassing suppression rules")
        }
        
        // Ask the coach brain what to do
        do {
            let decision = try await coachBrain.evaluateContext(context)
            
            // Log the decision for debugging
            logCoachDecision(context: context, decision: decision)
            
            // Act on the decision
            if decision.shouldSendMessage, let message = decision.message {
                try await messageDelivery.sendProactiveMessage(message)
                lastMessageTime = Date()
                todaysMessageCount += 1
            }
        } catch {
            print("❌ ProactiveScheduler: Evaluation failed: \(error)")
        }
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
    
    // MARK: - Background Task Management
    
    private func registerBackgroundTask() {
        // Note: This is now handled in AppDelegate to avoid launch timing issues
        print("📱 ProactiveScheduler: Background task handler registered in AppDelegate")
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
            print("📅 ProactiveScheduler: Scheduled next check in \(Int(settings.checkFrequency/60)) minutes")
        } catch {
            print("❌ ProactiveScheduler: Failed to schedule background task: \(error)")
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
    
    // MARK: - Helpers
    
    private func setupNotificationObservers() {
        // Listen for app opened from notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appOpenedFromNotification),
            name: Notification.Name("AppOpenedFromNotification"),
            object: nil
        )
    }
    
    @objc private func appOpenedFromNotification() {
        recordAppOpen()
    }
    
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
    
    private func logConfiguration() {
        print("   ↳ Check interval: \(Int(settings.checkFrequency/60)) minutes")
        print("   ↳ Max messages/day: \(settings.maxMessagesPerDay)")
        if let start = settings.quietHoursStart, let end = settings.quietHoursEnd {
            print("   ↳ Quiet hours: \(start):00 - \(end):00")
        }
    }
    
    private func logCoachDecision(context: CoachContext, decision: CoachDecision) {
        print("🤖 ProactiveScheduler Decision:")
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

// MARK: - Singleton Access (for backward compatibility)

extension ProactiveScheduler {
    static let shared = ProactiveScheduler()
}