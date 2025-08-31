# LLM-Driven Proactive Messaging Architecture

## Core Concept
Instead of complex scheduling and pattern analysis, we use a simple timer that wakes the LLM coach periodically. The coach evaluates the current context and decides whether to send a message.

## System Design

### 1. Simple Timer-Based Wake System

```swift
class ProactiveCoachManager {
    static let shared = ProactiveCoachManager()
    private var timer: Timer?
    private let checkInterval: TimeInterval = 30 * 60 // Check every 30 minutes
    
    func startProactiveMonitoring() {
        // Run on a background queue
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            Task {
                await self.evaluateAndAct()
            }
        }
    }
    
    private func evaluateAndAct() async {
        // Wake the coach with current context
        let context = gatherCurrentContext()
        let coachDecision = await askCoachWhatToDo(context: context)
        
        if coachDecision.shouldSendMessage {
            await sendProactiveMessage(coachDecision.message)
        }
    }
}
```

### 2. Context Gathering

```swift
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
    
    var contextPrompt: String {
        """
        CURRENT CONTEXT:
        - Time: \(formatTime(currentTime)) on \(dayOfWeek)
        - Training: Week \(weekNumber) of \(currentBlock) block
        - Today's workout: \(todaysWorkout ?? "Rest day")
        - Workout completed: \(workoutCompleted ? "Yes" : "No")
        - Last message sent: \(formatTimeSince(lastMessageTime))
        - Last workout: \(formatTimeSince(lastWorkoutTime))
        
        Based on this context, should you send a proactive message to the athlete?
        If yes, what message would be most helpful right now?
        """
    }
}
```

### 3. Coach Decision Making

```swift
struct CoachDecision {
    let shouldSendMessage: Bool
    let message: String?
    let reasoning: String // For logging/debugging
}

func askCoachWhatToDo(context: CoachContext) async -> CoachDecision {
    // Special system prompt for proactive evaluation
    let proactivePrompt = """
    You are evaluating whether to send a proactive message to your athlete.
    
    DECISION CRITERIA:
    - Only message if it adds value at this specific moment
    - Consider time of day and athlete's typical patterns
    - Don't be annoying or repetitive
    - Focus on timely reminders, check-ins, or motivational support
    
    \(context.contextPrompt)
    
    Respond with:
    SEND: [Yes/No]
    REASONING: [Why you made this decision]
    MESSAGE: [If Yes, the exact message to send]
    """
    
    // Call the LLM with this special prompt
    let response = await callLLM(systemPrompt: proactivePrompt)
    return parseCoachDecision(response)
}
```

### 4. Background Task Implementation

```swift
// Using iOS BackgroundTasks for more reliable execution
import BackgroundTasks

extension ProactiveCoachManager {
    func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: "com.trainer.coachCheck")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 min
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            let context = gatherCurrentContext()
            let decision = await askCoachWhatToDo(context: context)
            
            if decision.shouldSendMessage {
                // Create local notification
                await scheduleLocalNotification(message: decision.message!)
            }
            
            // Log decision for debugging
            logCoachDecision(context: context, decision: decision)
            
            // Schedule next check
            scheduleBackgroundCheck()
            
            task.setTaskCompleted(success: true)
        }
    }
}
```

### 5. Example Coach Decisions

#### Morning Check (7:30 AM, Tuesday)
**Context**: Tuesday workout planned, not completed, typical workout time 8 AM
**Decision**: SEND: Yes
**Reasoning**: "It's 30 minutes before the athlete's typical Tuesday workout time. A gentle reminder about today's Upper Body session would be timely."
**Message**: "Good morning! Ready for today's Upper Body work? Floor press 4×6, Pendlay Row 4×6, Pull-ups AMRAP. I'll check in after to see how it went. 💪"

#### Afternoon Check (2:00 PM, Tuesday)
**Context**: Tuesday workout planned, not completed, typical workout time 8 AM
**Decision**: SEND: Yes
**Reasoning**: "The athlete usually works out in the morning but hasn't logged today's session. A gentle check-in is appropriate."
**Message**: "Hey! Did you get your workout in today? If not, there's still time for an evening session. Let me know if you need to adjust the plan."

#### Evening Check (8:00 PM, Tuesday)
**Context**: Tuesday workout planned, completed at 5 PM
**Decision**: SEND: No
**Reasoning**: "Workout already completed today. No need for further messages unless it's a special milestone or Sunday review."

#### Sunday Review (7:00 PM, Sunday)
**Context**: End of week 3, 5/6 workouts completed
**Decision**: SEND: Yes
**Reasoning**: "Sunday evening is the perfect time for a weekly review to celebrate progress and preview next week."
**Message**: "Week 3 wrap-up! 🎯 You completed 5/6 workouts - solid consistency. Weight trending up nicely at 169.5 lbs. Ready to tackle Week 4 of Aerobic Capacity? Rest well tomorrow!"

### 6. Configuration Options

```swift
struct ProactiveMessagingSettings {
    var enabled: Bool = true
    var checkFrequency: TimeInterval = 30 * 60 // 30 minutes
    var quietHours: ClosedRange<Int>? = 22...6 // 10 PM to 6 AM
    var maxMessagesPerDay: Int = 3
    var sundayReviewTime: DateComponents = DateComponents(hour: 19) // 7 PM
}
```

### 7. Privacy & Intelligence Features

```swift
extension ProactiveCoachManager {
    private func shouldSuppressCheck(context: CoachContext) -> Bool {
        // Don't even wake the LLM if:
        // 1. In quiet hours
        if let quietHours = settings.quietHours {
            let hour = Calendar.current.component(.hour, from: context.currentTime)
            if quietHours.contains(hour) { return true }
        }
        
        // 2. Already sent max messages today
        if todaysMessageCount >= settings.maxMessagesPerDay { return true }
        
        // 3. User opened app in last 15 minutes
        if let lastOpen = lastAppOpenTime,
           Date().timeIntervalSince(lastOpen) < 15 * 60 { return true }
        
        return false
    }
}
```

## Key Advantages

1. **Leverages LLM Intelligence**: The coach already knows the training plan, context, and what's appropriate
2. **Contextually Aware**: Each decision is made with full context, not rigid rules
3. **Naturally Adaptive**: Automatically adjusts to schedule changes, missed workouts, etc.
4. **Simple Implementation**: No complex pattern matching or scheduling logic
5. **Easy to Debug**: Can log exactly why the coach decided to message or not
6. **Flexible**: Coach can send different types of messages based on context

## Implementation Steps

1. Add background task capability to Info.plist
2. Create ProactiveCoachManager singleton
3. Add special prompt handling for proactive evaluations
4. Implement local notification creation
5. Add settings UI for user control
6. Test with various scenarios

This approach trusts the LLM's judgment while giving users control over frequency and quiet hours.