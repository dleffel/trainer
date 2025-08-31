# Intelligent Onboarding with Enhanced Proactive Messaging

## Problem Statement
Currently, when no training program is set up, the proactive reminder system treats it as a "rest day" instead of helping users get started. This creates a poor onboarding experience where new users receive unhelpful messages.

## Solution Overview
We're enhancing the proactive messaging system to:
1. **Detect setup state** - Check if a program exists, health data is available, etc.
2. **Execute tool calls** - Use the same tools as the main chat to gather info and take actions
3. **Auto-initialize programs** - Follow the system prompt rules to start training when needed
4. **Send contextual messages** - Provide relevant nudges based on exact setup state

## Key Improvements

### 1. Smart Onboarding Flow
When the proactive check runs and finds no program:
- Automatically executes `[TOOL_CALL: get_training_status]` to verify
- If no program exists, executes `[TOOL_CALL: start_training_program]`
- Follows with `[TOOL_CALL: plan_week]` to set up the first week
- Sends a welcoming message: "I've set up your 20-week training program! Let's review today's workout..."

### 2. Setup State Detection
The system now recognizes multiple states:
- **No Program**: Auto-initializes and welcomes user
- **No Health Data**: Nudges to grant Health permissions for personalized zones
- **No API Key**: Guides user to complete API key setup
- **Fully Ready**: Provides contextual training reminders

### 3. Tool-Enabled Messages
Proactive messages can now:
- Check current training status
- Retrieve health data availability
- Initialize training programs
- Plan workout weeks
- All without user interaction!

### 4. Example Scenarios

#### Scenario 1: Brand New User
**Before**: "It's a rest day today!"
**After**: "Welcome to your rowing journey! I've initialized your 20-week training program. We're starting with an 8-week Aerobic Capacity block. Today calls for a 70-minute steady state row at 123-144 BPM. Ready to build that aerobic base?"

#### Scenario 2: Program Started, No Health Data
**Before**: Generic reminder about rest day
**After**: "Your training program is ready! 🚣‍♂️ To personalize your heart rate zones, please grant Health access in the app. This helps me tailor your workouts to your fitness level."

#### Scenario 3: Everything Set Up
**Before**: Basic workout reminder
**After**: "Time for today's threshold intervals! You've got 4×10' at 85-88% HR (158-163 BPM) at 24-26 spm. Remember to warm up properly and focus on consistent power application. You've got this! 💪"

## Technical Implementation

### Enhanced Context Structure
```swift
struct CoachContext {
    // Existing workout context
    let currentTime: Date
    let todaysWorkout: String?
    let workoutCompleted: Bool
    
    // New setup context
    let programExists: Bool
    let hasHealthData: Bool
    let messagesSentToday: Int
}
```

### Multi-Turn LLM Flow
1. Initial LLM call with full system prompt
2. Process any tool calls through ToolProcessor
3. Follow-up LLM call with tool results
4. Generate final contextual message

### System Prompt Integration
The proactive messaging now includes:
- Full rowing coach system prompt
- Tool availability and usage instructions
- Automatic initialization rules (Section 8)
- Context-aware decision criteria

## Benefits

1. **Zero-Friction Onboarding**: New users get their program set up automatically
2. **Intelligent Nudging**: Messages adapt to exact setup state
3. **Proactive Problem Solving**: Coach identifies and helps resolve setup issues
4. **Consistent Experience**: Same coaching intelligence in proactive messages as main chat

## Implementation Checklist
- [x] Design enhanced context structure
- [x] Create tool-enabled LLM prompts
- [x] Plan multi-turn execution flow
- [x] Define setup state messages
- [ ] Implement in ProactiveCoachManager
- [ ] Test with various scenarios
- [ ] Deploy and monitor

## Next Steps
Switch to Code mode to implement these enhancements in the ProactiveCoachManager.swift file.