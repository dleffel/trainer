# Training Calendar Fix Plan

## Problem
The AI coach returns text descriptions of workouts instead of using tools to save them to the calendar. This results in empty calendar views despite detailed workout descriptions.

## Root Cause
The SystemPrompt.md lacks enforcement of tool usage. The AI describes workouts but never calls:
1. `start_training_program` to initialize
2. `plan_week_workouts` to save data

## Solution: Add Section 9.5 to SystemPrompt.md

### 9.5 │ MANDATORY TOOL USAGE RULES

**CRITICAL: You MUST use tools for ALL calendar operations. Text-only responses are FORBIDDEN for:**

• **Program Initialization**: When get_training_status shows "No program started":
  → You MUST call [TOOL_CALL: start_training_program] BEFORE any workout description
  → You MUST follow with [TOOL_CALL: plan_week_workouts] to save the workouts
  → NEVER just describe workouts without saving them

• **Workout Planning**: When describing any week's workouts:
  → You MUST call [TOOL_CALL: plan_week_workouts] with the actual workout details
  → The workouts parameter MUST contain the full workout descriptions
  → Text descriptions WITHOUT tool calls will NOT appear in the calendar

• **Rule Enforcement**:
  → If you describe workouts without using plan_week_workouts, they WILL NOT be saved
  → If you say "I've initialized" without calling start_training_program, it DID NOT happen
  → The calendar ONLY displays data saved through tools, NOT text responses

**Example of CORRECT behavior:**
```
User: "Start my training"
Coach: [TOOL_CALL: get_training_status]
Result: "No program started"
Coach: [TOOL_CALL: start_training_program]
Result: "Program created"
Coach: [TOOL_CALL: plan_week_workouts(week_start_date: "2024-09-01", workouts: {
  "monday": "Full rest - recovery only",
  "tuesday": "Lower 1: Squat 3×5 @ 225lb...",
  ...
})]
Result: "Week planned"
Coach: "I've initialized your program and planned Week 1..."
```

## Implementation Steps
1. Add section 9.5 to SystemPrompt.md
2. Test that the coach now uses tools properly
3. Verify calendar displays saved workouts

## Success Criteria
- Coach calls start_training_program when no program exists
- Coach calls plan_week_workouts with actual workout content
- Calendar shows the saved workouts