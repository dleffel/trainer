# Enhanced Proactive Messaging Implementation Plan

## 1. Enhanced LLM Prompt Structure

### Full System Prompt Integration
```swift
private func buildEnhancedSystemPrompt() -> String {
    // Load the full rowing coach system prompt
    let systemPrompt = SystemPromptLoader.loadSystemPrompt() ?? ""
    
    return """
    \(systemPrompt)
    
    ## PROACTIVE MESSAGING MODE
    
    You are evaluating whether to send a proactive message to your athlete.
    This is a background check - the athlete hasn't opened the app.
    
    ### PROACTIVE DECISION CRITERIA:
    1. Check setup state first - if no program exists, initialize it
    2. Only message if it adds value at this specific moment
    3. Consider time of day and athlete's typical patterns
    4. Don't be annoying or repetitive
    5. Focus on timely reminders, check-ins, or motivational support
    
    ### TOOL USAGE IN PROACTIVE MODE:
    You have access to the same tools as in regular chat:
    - [TOOL_CALL: get_training_status] to check program state
    - [TOOL_CALL: get_health_data] to check available metrics
    - [TOOL_CALL: start_training_program] to initialize if needed
    - [TOOL_CALL: plan_week] to set up the first week
    - [TOOL_CALL: get_weekly_schedule] to check current plan
    
    ### SETUP STATE HANDLING:
    If get_training_status returns "No program started":
    1. IMMEDIATELY use [TOOL_CALL: start_training_program]
    2. Follow with [TOOL_CALL: plan_week]
    3. Message: "I've set up your 20-week training program! Let's review..."
    
    ### RESPONSE FORMAT:
    First, use any necessary tools to gather information or take actions.
    Then provide your final evaluation:
    
    SEND: [Yes/No]
    REASONING: [One sentence explaining why]
    MESSAGE: [If Yes, the exact message to send to the athlete]
    """
}
```

## 2. Multi-Turn Tool Execution Flow

### Enhanced askCoachWhatToDo Method
```swift
private func askCoachWhatToDo(context: CoachContext) async -> CoachDecision {
    print("🤔 ProactiveCoachManager: Starting enhanced evaluation...")
    
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
    
    First, check the current state using available tools if needed.
    Then decide whether to send a message.
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
            let followUpPrompt = """
            Based on the tool results:
            \(toolResultsFormatted)
            
            Now provide your final decision:
            SEND: [Yes/No]
            REASONING: [One sentence explaining why]
            MESSAGE: [If Yes, the exact message to send to the athlete]
            """
            
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
```

### Tool Processing for Proactive Messages
```swift
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
```

## 3. Enhanced Context Structure

### Updated CoachContext
```swift
struct CoachContext {
    // Existing fields
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
```

### Updated gatherCurrentContext Method
```swift
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
```

## 4. Setup State Message Templates

### Message Generation Based on State
```swift
private func generateSetupMessage(for state: SetupState) -> String {
    switch state {
    case .noProgramNoData:
        return "Welcome to your rowing journey! I've just set up your personalized 20-week training program. We're starting with an 8-week Aerobic Capacity block to build your foundation. Ready to see today's workout?"
        
    case .programStartedNoHealth:
        return "Your training program is ready! 🚣‍♂️ To personalize your heart rate zones, please grant Health access in the app. This helps me tailor your workouts to your fitness level."
        
    case .everythingReady(let workout):
        return "Time for today's \(workout)! Remember to warm up properly and focus on consistent stroke rate. You've got this! 💪"
        
    case .missedWorkouts(let days):
        return "Haven't seen you in \(days) days - everything okay? Today's a great day to get back on track. Your \(getCurrentWorkoutType()) is waiting!"
        
    case .weeklyReview:
        return "Week \(scheduleManager.currentWeek) complete! You hit \(getWeeklyCompletionRate())% of your workouts. Ready to review your progress and plan for next week?"
    }
}

enum SetupState {
    case noProgramNoData
    case programStartedNoHealth
    case everythingReady(workout: String)
    case missedWorkouts(days: Int)
    case weeklyReview
}
```

## 5. Testing Scenarios

### Test Cases
1. **Fresh Install Test**
   - No program exists
   - Should auto-initialize and send welcome message
   
2. **Partial Setup Test**
   - Program exists but no health data
   - Should nudge for Health permissions
   
3. **Complete Setup Test**
   - Everything configured
   - Should send contextual training reminders
   
4. **Tool Failure Test**
   - Tool calls fail
   - Should fallback to basic nudge messages

### Debug Logging
Enhanced logging throughout the flow:
- Tool detection and execution
- LLM calls and responses
- State transitions
- Message generation

## 6. Implementation Steps

1. Update `CoachContext` struct with new fields
2. Modify `gatherCurrentContext()` to populate new fields
3. Create `buildEnhancedSystemPrompt()` method
4. Update `askCoachWhatToDo()` for multi-turn support
5. Add `processProactiveToolCalls()` method
6. Implement state-based message templates
7. Test with various scenarios
8. Document behavior changes