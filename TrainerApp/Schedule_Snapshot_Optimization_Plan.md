# Schedule Snapshot Optimization Plan

## Overview
Reduce tool call chains by embedding a workout schedule snapshot (today + last 3 weeks) directly in the system prompt, allowing the coach to make immediate decisions without requiring tool calls for basic schedule queries.

## Current State Analysis

### Tool Call Overhead
Every coaching interaction currently requires:
1. `get_training_status` - Check program & phase
2. `get_workout(date: "today")` - Check today's workout
3. `plan_workout(...)` - Create workout if needed

This results in:
- 2-3 tool calls minimum per interaction
- Increased latency and conversation complexity
- Redundant schedule lookups
- Complex parsing in ToolProcessor

### Benefits of Optimization
- **Performance**: Fewer API calls = faster responses
- **Simplicity**: Less complex conversation flow
- **Reliability**: Less dependency on tool call parsing
- **User Experience**: Quicker, more responsive coaching

## Implementation Plan

### 1. Schedule Snapshot Format Design

Create a structured format for embedding schedule data:

```
## CURRENT SCHEDULE SNAPSHOT
**Generated**: 2024-09-20 @ 19:27 PST
**Program**: Week 5 of 20 - Hypertrophy-Strength Block (Week 5 of 10)
**Current Date**: Friday, September 20, 2024

### THIS WEEK (Sep 16-22, 2024)
- **Monday 9/16**: Full Rest ✓ (completed)
- **Tuesday 9/17**: 70min Steady Row @ Zone 2 ✓ (completed - felt strong)
- **Wednesday 9/18**: Upper Body Strength - Bench 3×8, Rows 3×10 ✓ (completed)
- **Thursday 9/19**: 60min Zone 2 Bike + Mobility ✓ (completed)
- **Friday 9/20**: Lower Body Strength - Squats 3×5, RDL 3×8 ⚡ (TODAY - NO WORKOUT PLANNED)
- **Saturday 9/21**: (no workout planned)
- **Sunday 9/22**: (no workout planned)

### LAST 7 DAYS COMPLETED
- **Fri 9/13**: Lower Body - Squats 3×5 @ 225lb, RDL 3×8 @ 185lb ✓
- **Thu 9/12**: 60min Zone 2 Row @ 150W ✓ (felt easy, good recovery)
- **Wed 9/11**: Upper Body - Bench 3×8 @ 185lb, Rows 3×10 @ 155lb ✓
- **Tue 9/10**: 75min Steady Row @ Zone 2 ✓ (strong session)
- **Mon 9/9**: Full Rest ✓
- **Sun 9/8**: 90min Long Row + Strength ✓ (demanding but completed)
- **Sat 9/7**: Upper Body - Bench 3×8 @ 180lb, Pull-ups 3×10 ✓

### SAME DAY PROGRESSION (Last 3 Fridays)
- **Today (Fri 9/20)**: Lower Body Strength ⚡ (PLANNED - NO WORKOUT YET)
- **Fri 9/13**: Squats 3×5 @ 225lb, RDL 3×8 @ 185lb ✓ (felt strong)
- **Fri 9/6**: Squats 3×5 @ 220lb, RDL 3×8 @ 180lb ✓ (good session)
- **Fri 8/30**: Squats 3×5 @ 215lb, RDL 3×8 @ 175lb ✓ (building strength)
```

### 2. SystemPromptLoader Enhancement

Modify [`SystemPromptLoader.swift`](TrainerApp/TrainerApp/Utilities/SystemPromptLoader.swift) to:

```swift
// Add schedule injection capability
func loadSystemPromptWithSchedule() -> String {
    let basePrompt = loadSystemPrompt()
    let scheduleSnapshot = TrainingScheduleManager.shared.generateScheduleSnapshot()
    return basePrompt + "\n\n" + scheduleSnapshot
}
```

### 3. TrainingScheduleManager Schedule Generation

Add to [`TrainingScheduleManager.swift`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:4-807):

```swift
/// Generate schedule snapshot for system prompt injection
func generateScheduleSnapshot() -> String {
    guard let program = currentProgram else {
        return "## CURRENT SCHEDULE SNAPSHOT\n**Status**: No active training program"
    }
    
    let current = Date.current
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    
    var snapshot = "## CURRENT SCHEDULE SNAPSHOT\n"
    snapshot += "**Generated**: \(current) \n"
    snapshot += "**Program**: Week \(totalWeekInProgram) of 20 - \(currentBlock?.type.rawValue ?? "Unknown") Block\n"
    snapshot += "**Current Date**: \(formatter.string(from: current))\n\n"
    
    // Add this week
    snapshot += generateWeekSnapshot(for: current, title: "THIS WEEK")
    
    // Add last 7 days with loads and performance
    snapshot += generateLast7DaysWithLoads()
    
    // Add same day progression (last 3 occurrences of current day)
    snapshot += generateSameDayProgression(for: current)
    
    return snapshot
}

/// Generate last 7 completed days with actual loads and performance notes
private func generateLast7DaysWithLoads() -> String {
    var section = "### LAST 7 DAYS COMPLETED\n"
    let calendar = Calendar.current
    
    for i in 1...7 {
        if let pastDate = calendar.date(byAdding: .day, value: -i, to: Date.current),
           let workoutDay = getWorkoutDay(for: pastDate),
           let workout = workoutDay.plannedWorkout,
           workoutDay.isCompleted {
            
            let dayName = DateFormatter().weekdaySymbols[calendar.component(.weekday, from: pastDate) - 1]
            let shortDate = formatShortDate(pastDate)
            
            // Extract key load information from structured workout
            let loadInfo = extractLoadSummary(from: workoutDay)
            let notes = workoutDay.completionNotes.isEmpty ? "" : " (\(workoutDay.completionNotes))"
            
            section += "- **\(dayName) \(shortDate)**: \(loadInfo) ✓\(notes)\n"
        }
    }
    section += "\n"
    return section
}

/// Generate same day progression for load tracking
private func generateSameDayProgression(for date: Date) -> String {
    let calendar = Calendar.current
    let dayOfWeek = calendar.component(.weekday, from: date)
    let dayName = DateFormatter().weekdaySymbols[dayOfWeek - 1]
    
    var section = "### SAME DAY PROGRESSION (Last 3 \(dayName)s)\n"
    
    // Today's planned workout
    if let todayWorkout = getWorkoutDay(for: date) {
        let loadInfo = todayWorkout.plannedWorkout != nil ?
            extractLoadSummary(from: todayWorkout) : "No workout planned"
        section += "- **Today (\(dayName) \(formatShortDate(date)))**: \(loadInfo) ⚡ (PLANNED)\n"
    }
    
    // Previous 3 occurrences of same day
    for weekOffset in 1...3 {
        if let pastDate = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: date),
           let workoutDay = getWorkoutDay(for: pastDate),
           workoutDay.isCompleted {
            
            let loadInfo = extractLoadSummary(from: workoutDay)
            let notes = workoutDay.completionNotes.isEmpty ? "" : " (\(workoutDay.completionNotes))"
            section += "- **\(dayName) \(formatShortDate(pastDate))**: \(loadInfo) ✓\(notes)\n"
        }
    }
    
    return section
}

/// Extract key load information from workout for snapshot
private func extractLoadSummary(from workoutDay: WorkoutDay) -> String {
    // Parse structured workout for key exercises and loads
    if let structured = workoutDay.structuredWorkout {
        var loadSummary: [String] = []
        
        for exercise in structured.exercises {
            if exercise.kind == "strength",
               let movement = exercise.detail["movement"] as? String,
               let sets = exercise.detail["sets"] as? [[String: Any]] {
                
                // Extract primary set info (usually the working sets)
                if let firstSet = sets.first,
                   let reps = firstSet["reps"] as? Int,
                   let weight = firstSet["weight"] as? String {
                    let exerciseName = formatExerciseName(movement)
                    loadSummary.append("\(exerciseName) \(sets.count)×\(reps) @ \(weight)")
                }
            } else if exercise.kind.contains("cardio") {
                // Extract cardio summary
                if let duration = exercise.detail["durationMinutes"] as? Int {
                    loadSummary.append("\(duration)min \(exercise.name)")
                }
            }
        }
        
        return loadSummary.isEmpty ? workoutDay.plannedWorkout ?? "Workout" : loadSummary.joined(separator: ", ")
    }
    
    // Fallback to planned workout text
    return workoutDay.plannedWorkout ?? "Workout"
}
```

### 4. Updated Coach Workflow

Modify SystemPrompt Section 9.1 to use embedded schedule:

```markdown
### 9.1 │ OPTIMIZED SESSION WORKFLOW

**Purpose**: Use embedded schedule snapshot to minimize tool calls.

**Decision Logic:**
1. **Check embedded schedule snapshot above** for today's status
2. **If today has a workout planned**: Discuss/review with athlete
3. **If today has NO workout planned**: Use `[TOOL_CALL: plan_workout]` to create one
4. **Only use `get_training_status` if schedule snapshot is stale (>1 hour old)**

**Tool Call Reduction:**
- ✅ Immediate access to schedule without `get_training_status`
- ✅ Immediate access to today's workout without `get_workout` 
- ✅ Only need `plan_workout` when no workout exists for today
- ✅ 90% reduction in tool calls for basic coaching interactions
```

### 5. ConversationManager Integration

Update [`ConversationManager.swift`](TrainerApp/TrainerApp/Services/ConversationManager.swift:24-38) to use enhanced system prompt:

```swift
// Replace current systemPrompt parameter with:
let enhancedSystemPrompt = SystemPromptLoader.shared.loadSystemPromptWithSchedule()

// Use enhancedSystemPrompt in LLMClient calls
```

### 6. Fallback & Edge Cases

Handle scenarios where tool calls are still needed:
- **Stale snapshot** (>1 hour old): Fall back to tool calls
- **No workout for today**: Use `plan_workout` tool
- **Schedule modifications**: Regenerate snapshot
- **Program initialization**: Use full tool workflow

### 7. Performance Considerations

**Schedule Snapshot Regeneration Triggers:**
- App launch/resume
- After any workout planning/modification
- Hourly background refresh
- User manual refresh

**System Prompt Size Management:**
- Limit to 4 weeks max (today + 3 weeks back)
- Compress older weeks to summary format
- Remove verbose details from completed workouts

## Implementation Steps

### Phase 1: Core Infrastructure
1. Add `generateScheduleSnapshot()` to TrainingScheduleManager
2. Enhance SystemPromptLoader with schedule injection
3. Create snapshot format and templates

### Phase 2: Integration
4. Update ConversationManager to use enhanced prompts
5. Modify SystemPrompt.md with new workflow
6. Add snapshot regeneration triggers

### Phase 3: Optimization & Testing  
7. Implement performance optimizations
8. Add fallback logic for edge cases
9. Test with various schedule states and scenarios

## Success Metrics

- **Tool Call Reduction**: 90% fewer tool calls for basic interactions
- **Response Time**: 2-3x faster coaching responses
- **User Experience**: More immediate, conversational coaching
- **Reliability**: Fewer parsing errors and tool call failures

## Risks & Mitigations

**Risk**: System prompt becomes too large
**Mitigation**: Limit snapshot to essential data, compress older entries

**Risk**: Stale schedule data
**Mitigation**: Smart regeneration triggers, fallback to tool calls

**Risk**: Breaking existing workflows
**Mitigation**: Maintain tool call compatibility, gradual rollout

## Future Enhancements

- **Smart prefetch**: Predict next likely requests
- **Contextual snapshots**: Include relevant training context
- **Adaptive freshness**: Vary refresh rate based on usage patterns