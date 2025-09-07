# Adaptive Planning Implementation Steps

Based on the decision to implement full CRUD operations with day-by-day adaptive planning for maximum flexibility.

## Phase 1: Tool Implementation (ToolProcessor.swift)

### 1.1 Add New Tool Cases
```swift
// In detectAndExecuteTools method, add cases:

case "plan_workout":
    // Plan a single day's workout
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let workoutParam = toolCall.parameters["workout"] as? String ?? ""
    let notesParam = toolCall.parameters["notes"] as? String
    return try await executePlanWorkout(date: dateParam, workout: workoutParam, notes: notesParam)

case "update_workout":
    // Update an existing workout with reason
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let workoutParam = toolCall.parameters["workout"] as? String ?? ""
    let reasonParam = toolCall.parameters["reason"] as? String
    return try await executeUpdateWorkout(date: dateParam, workout: workoutParam, reason: reasonParam)

case "delete_workout":
    // Remove a planned workout
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let reasonParam = toolCall.parameters["reason"] as? String
    return try await executeDeleteWorkout(date: dateParam, reason: reasonParam)

case "get_workout":
    // Read specific day's workout
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    return try await executeGetWorkout(date: dateParam)

case "plan_next_workout":
    // Adaptive planning based on feedback
    let feedbackParam = toolCall.parameters["based_on_feedback"] as? String
    let nextDateParam = toolCall.parameters["next_date"] as? String
    return try await executePlanNextWorkout(feedback: feedbackParam, nextDate: nextDateParam)
```

### 1.2 Implement Tool Execution Methods
```swift
private func executePlanWorkout(date: String, workout: String, notes: String?) async throws -> String {
    return await MainActor.run {
        let manager = TrainingScheduleManager.shared
        let targetDate = parseDate(date)
        
        if manager.planWorkout(for: targetDate, workout: workout, notes: notes) {
            return """
            [Workout Planned]
            • Date: \(formatDate(targetDate))
            • Workout: \(workout)
            \(notes != nil ? "• Notes: \(notes!)" : "")
            • Status: Saved to calendar
            """
        } else {
            return "[Error: Could not plan workout for \(date)]"
        }
    }
}

private func executeUpdateWorkout(date: String, workout: String, reason: String?) async throws -> String {
    return await MainActor.run {
        let manager = TrainingScheduleManager.shared
        let targetDate = parseDate(date)
        
        if let existingWorkout = manager.getWorkout(for: targetDate) {
            let previousWorkout = existingWorkout.plannedWorkout ?? "None"
            
            if manager.updateWorkout(for: targetDate, workout: workout, reason: reason) {
                return """
                [Workout Updated]
                • Date: \(formatDate(targetDate))
                • Previous: \(previousWorkout)
                • Updated to: \(workout)
                \(reason != nil ? "• Reason: \(reason!)" : "")
                """
            }
        }
        return "[Error: Could not update workout for \(date)]"
    }
}

private func executeDeleteWorkout(date: String, reason: String?) async throws -> String {
    return await MainActor.run {
        let manager = TrainingScheduleManager.shared
        let targetDate = parseDate(date)
        
        if manager.deleteWorkout(for: targetDate, reason: reason) {
            return """
            [Workout Deleted]
            • Date: \(formatDate(targetDate))
            \(reason != nil ? "• Reason: \(reason!)" : "")
            • Status: Removed from calendar
            """
        } else {
            return "[Error: Could not delete workout for \(date)]"
        }
    }
}

private func executePlanNextWorkout(feedback: String?, nextDate: String?) async throws -> String {
    return await MainActor.run {
        let manager = TrainingScheduleManager.shared
        
        // Get the next training date
        let targetDate: Date
        if let nextDate = nextDate {
            targetDate = parseDate(nextDate)
        } else {
            // Find next training day (skip rest days)
            targetDate = manager.getNextTrainingDate() ?? Date().addingTimeInterval(86400)
        }
        
        // Generate adaptive workout based on feedback
        let adaptiveWorkout = manager.generateAdaptiveWorkout(
            basedOnFeedback: feedback,
            forDate: targetDate
        )
        
        if manager.planWorkout(for: targetDate, workout: adaptiveWorkout, notes: "Adapted based on: \(feedback ?? "previous performance")") {
            return """
            [Adaptive Workout Planned]
            • Date: \(formatDate(targetDate))
            • Based on: \(feedback ?? "previous performance")
            • Workout: \(adaptiveWorkout)
            • Status: Saved to calendar
            """
        } else {
            return "[Error: Could not plan adaptive workout]"
        }
    }
}
```

## Phase 2: TrainingScheduleManager Updates

### 2.1 Add Single-Day Operations
```swift
// In TrainingScheduleManager.swift

func planWorkout(for date: Date, workout: String, notes: String?) -> Bool {
    // Find or create workout day
    if let existingDay = getWorkout(for: date) {
        // Update existing
        var updatedDay = existingDay
        updatedDay.plannedWorkout = workout
        updatedDay.coachNotes = notes
        updatedDay.lastModified = Date()
        updatedDay.isCoachPlanned = true
        return updateWorkoutDay(updatedDay)
    } else {
        // Create new
        let newDay = WorkoutDay(
            date: date,
            blockType: currentBlock?.type ?? .aerobicCapacity,
            plannedWorkout: workout
        )
        newDay.coachNotes = notes
        newDay.isCoachPlanned = true
        return addWorkoutDay(newDay)
    }
}

func updateWorkout(for date: Date, workout: String, reason: String?) -> Bool {
    guard var workoutDay = getWorkout(for: date) else { return false }
    
    workoutDay.previousWorkout = workoutDay.plannedWorkout
    workoutDay.plannedWorkout = workout
    workoutDay.modificationReason = reason
    workoutDay.lastModified = Date()
    
    return updateWorkoutDay(workoutDay)
}

func deleteWorkout(for date: Date, reason: String?) -> Bool {
    guard var workoutDay = getWorkout(for: date) else { return false }
    
    workoutDay.plannedWorkout = nil
    workoutDay.deletionReason = reason
    workoutDay.lastModified = Date()
    
    return updateWorkoutDay(workoutDay)
}

func generateAdaptiveWorkout(basedOnFeedback: String?, forDate date: Date) -> String {
    // Analyze feedback and generate appropriate workout
    let feedback = basedOnFeedback?.lowercased() ?? ""
    let currentBlock = getCurrentBlock(for: date)
    
    // Adaptive logic based on feedback
    if feedback.contains("tired") || feedback.contains("heavy") || feedback.contains("fatigue") {
        // Reduce intensity
        return generateRecoveryWorkout(for: currentBlock)
    } else if feedback.contains("strong") || feedback.contains("great") || feedback.contains("easy") {
        // Maintain or slightly increase
        return generateProgressiveWorkout(for: currentBlock)
    } else if feedback.contains("sore") || feedback.contains("pain") {
        // Active recovery
        return generateActiveRecoveryWorkout()
    } else {
        // Standard progression
        return generateStandardWorkout(for: currentBlock, date: date)
    }
}
```

### 2.2 Update WorkoutDay Model
```swift
// In TrainingCalendar.swift, update WorkoutDay struct:

struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    var plannedWorkout: String?
    var isCoachPlanned: Bool = false
    
    // New fields for adaptive planning
    var coachNotes: String?
    var lastModified: Date?
    var previousWorkout: String?
    var modificationReason: String?
    var deletionReason: String?
    var plannedIntensity: IntensityLevel?
    var adaptationNotes: String?
}

enum IntensityLevel: String, Codable {
    case recovery = "Recovery"
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case maximum = "Maximum"
}
```

## Phase 3: System Prompt Updates

### 3.1 Replace Section 9.5 with Adaptive Protocol
```markdown
## 9.5 │ ADAPTIVE PLANNING PROTOCOL

**CORE PRINCIPLE: Plan one day at a time, adapt based on feedback**

### Daily Workflow:
1. Morning: Plan today's workout only
2. Post-workout: Collect feedback
3. Next day: Use feedback to inform planning
4. Continuous: Adjust based on life circumstances

### Tool Usage Pattern:
```
# Day 1 Morning
Athlete: "What's today's workout?"
Coach: [TOOL_CALL: get_training_status]
Coach: [TOOL_CALL: plan_workout(date: "today", workout: "70-min steady row @ Zone 2")]
"Today: 70-minute steady row at Zone 2, keep heart rate 135-145..."

# Day 1 Evening
Athlete: "Done, legs were heavy, cut it to 60 min"
Coach: [TOOL_CALL: mark_workout_complete(date: "today", workout: "60 min steady row", notes: "legs heavy")]
Coach: [TOOL_CALL: plan_next_workout(based_on_feedback: "legs heavy, shortened to 60 min")]
"Good call. Tomorrow: 45-minute recovery bike to help those legs recover..."

# Day 2 Morning (if feeling better)
Athlete: "Legs feel much better today"
Coach: [TOOL_CALL: update_workout(date: "today", workout: "60-min steady row @ Zone 2", reason: "athlete recovered well")]
"Great! Updated to 60-minute steady row since you're feeling better..."
```

### Modification Rules:
• Heavy fatigue → Reduce volume 20-30%
• Poor sleep → Maintain movement, reduce intensity
• Feeling strong → Option to add 10-15%
• Life stress → Switch to recovery focus
```

### 3.2 Add New Tool Documentation
```markdown
## 14.9 │ plan_workout
• Plans a single day's workout with details
• Parameters: date (default "today"), workout (required), notes (optional)
• Usage: [TOOL_CALL: plan_workout(date: "today", workout: "70-min row @ UT2")]

## 14.10 │ update_workout
• Modifies an existing planned workout
• Parameters: date, workout, reason (why the change)
• Usage: [TOOL_CALL: update_workout(date: "today", workout: "45-min recovery", reason: "fatigue")]

## 14.11 │ delete_workout
• Removes a planned workout (unplanned rest)
• Parameters: date, reason
• Usage: [TOOL_CALL: delete_workout(date: "today", reason: "feeling unwell")]

## 14.12 │ get_workout
• Retrieves specific day's workout details
• Parameters: date
• Usage: [TOOL_CALL: get_workout(date: "tomorrow")]

## 14.13 │ plan_next_workout
• Plans next workout based on recent feedback
• Parameters: based_on_feedback, next_date (optional)
• Usage: [TOOL_CALL: plan_next_workout(based_on_feedback: "felt strong today")]
```

## Phase 4: Migration Strategy

### 4.1 Backward Compatibility
- Keep `plan_week_workouts` functional but deprecated
- System prompt encourages single-day planning
- Both approaches work during transition

### 4.2 Testing Sequence
1. Test individual CRUD operations
2. Test adaptive planning flow
3. Test modification scenarios
4. Test edge cases (missing days, conflicts)

### 4.3 Rollout Plan
1. Deploy code changes (keep old tools working)
2. Update system prompt to prefer new tools
3. Monitor coach behavior for 1 week
4. Remove deprecated weekly planning guidance
5. Optional: Remove plan_week_workouts after 30 days

## Success Metrics
- Reduction in "workout too hard/easy" feedback
- Increase in workout completion rate
- More workout modifications (shows responsiveness)
- Positive athlete feedback on flexibility