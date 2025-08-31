# Enhanced Proactive Messaging Architecture

## Overview
This design enhances the proactive messaging system to intelligently guide users through app setup, automatically initialize training programs when possible, and provide contextual nudges based on the current state.

## Key Enhancements

### 1. Multi-Turn Tool-Enabled Conversations
- Proactive messages can now execute tool calls to gather information and take actions
- Uses the same tool detection and execution infrastructure as the main chat
- Supports automatic program initialization per system prompt rules

### 2. Enhanced Context Gathering
```swift
struct EnhancedCoachContext {
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
    
    // New fields for setup detection
    let programExists: Bool
    let hasHealthKitPermissions: Bool
    let hasNotificationPermissions: Bool
    let hasApiKey: Bool
    let daysSinceInstall: Int
    let totalMessagesSent: Int
    let hasCompletedOnboarding: Bool
}
```

### 3. Intelligent Decision Flow

```
┌─────────────────────────┐
│ Proactive Check Trigger │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   Gather Context        │
│ (Enhanced with setup)   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Check Suppression Rules │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  LLM Evaluation with    │
│  System Prompt & Tools  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Execute Tool Calls      │
│ (if any)                │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Generate Final Message  │
│ Based on Tool Results   │
└─────────────────────────┘
```

### 4. Enhanced LLM Prompting Structure

```swift
let enhancedSystemPrompt = """
You are evaluating whether to send a proactive message to your athlete.

CORE IDENTITY:
\(loadSystemPrompt()) // Include full rowing coach system prompt

AVAILABLE TOOLS:
- [TOOL_CALL: get_training_status] - Check if program exists
- [TOOL_CALL: get_health_data] - Check health data availability
- [TOOL_CALL: start_training_program] - Initialize training if needed
- [TOOL_CALL: plan_week] - Plan the first week

DECISION FRAMEWORK:
1. First, check the current setup state using tools
2. If no program exists, follow Section 8 initialization rules
3. Generate appropriate message based on findings
"""
```

### 5. Setup State Categories

#### State 1: No Program Started
- **Detection**: `programExists == false`
- **Action**: Use tools to check status and initialize program
- **Message**: "I've set up your 20-week training program! Let's review today's workout..."

#### State 2: Program Started, No Health Data
- **Detection**: `programExists == true && recentMetrics == nil`
- **Message**: "Your training is set up! To personalize your heart rate zones, please grant Health access in the app."

#### State 3: Missing API Key
- **Detection**: `hasApiKey == false`
- **Message**: "Ready to start training? Open the app to complete setup with your API key."

#### State 4: Everything Ready
- **Detection**: All setup complete
- **Action**: Normal proactive coaching based on training context

### 6. Implementation Changes

#### ProactiveCoachManager Updates:
1. Add `executeToolCalls()` method
2. Enhance `askCoachWhatToDo()` to support multi-turn
3. Update `CoachDecision` to include tool execution results
4. Add setup state detection methods

#### New Methods:
```swift
private func executeProactiveToolCalls(_ response: String) async -> (processedResponse: String, toolResults: [ToolCallResult]) {
    // Use ToolProcessor to handle tool calls
    let processed = try await ToolProcessor.shared.processResponseWithToolCalls(response)
    return (processed.cleanedResponse, processed.toolResults)
}

private func performMultiTurnEvaluation(context: EnhancedCoachContext) async -> CoachDecision {
    // Initial LLM call with system prompt and context
    // Execute any tool calls
    // Final LLM call with tool results to generate message
}
```

### 7. Message Templates by State

#### Onboarding Messages:
```
"👋 Welcome to your rowing journey! I've initialized your 20-week training program. We're starting with an 8-week Aerobic Capacity block. Ready to see today's workout?"

"🚀 Your training program is all set! Today is {day} - {workout_summary}. Open the app when you're ready to start."

"💪 Great timing! I've set up your personalized program. Based on your schedule, today calls for {specific_workout}. Let's build that aerobic base!"
```

#### Setup Nudges:
```
"🏃‍♂️ Your program is ready, but I need your health data to personalize heart rate zones. Grant Health access in Settings to unlock personalized training."

"📊 Almost there! Add your API key in the app settings so I can provide real-time coaching during workouts."
```

#### Training Reminders:
```
"🚣‍♂️ Ready for today's {workout_type}? You've got {duration} of {intensity} work planned. Perfect weather for it!"

"✅ Yesterday's workout was solid! Today is your {day_type} day - {specific_guidance}."
```

### 8. Error Handling

- Tool call failures don't block messaging
- Fallback to basic nudges if tools unavailable
- Clear error messages guide users to resolution

### 9. Benefits

1. **Zero-Friction Onboarding**: Program initializes automatically on first check
2. **Intelligent Nudging**: Messages adapt to exact setup state
3. **Proactive Problem Solving**: Coach identifies and helps resolve setup issues
4. **Seamless Experience**: Users feel guided, not nagged

### 10. Testing Scenarios

1. **Fresh Install**: No program, no permissions
2. **Partial Setup**: Program exists, missing health data
3. **Complete Setup**: Everything configured
4. **Re-engagement**: User hasn't opened app in days
5. **Mid-Program**: Various training states