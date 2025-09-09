# Coach-Selected Workout Icons Implementation Plan

## Goal
Allow the coach to specify workout icons when planning workouts, replacing the current hard-coded day-based icons with contextual icons that reflect the actual workout content.

## Implementation Steps

### 1. Data Model Updates

#### 1.1 Update WorkoutDay Model
```swift
// In TrainingCalendar.swift
struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    var plannedWorkout: String?
    var isCoachPlanned: Bool = false
    
    // NEW: Coach-selected icon
    var workoutIcon: String?  // SF Symbol name selected by coach
}
```

#### 1.2 Create WorkoutType Enum
```swift
// In TrainingCalendar.swift
enum WorkoutType: String, CaseIterable {
    case rest = "bed.double.fill"
    case rowing = "figure.rower"
    case cycling = "bicycle"
    case running = "figure.run"
    case strength = "figure.strengthtraining.traditional"
    case yoga = "figure.yoga"
    case swimming = "figure.pool.swim"
    case crossTraining = "figure.mixed.cardio"
    case recovery = "heart.fill"
    case testing = "chart.line.uptrend.xyaxis"
    case noWorkout = "calendar.badge.exclamationmark"
    
    var icon: String {
        return self.rawValue
    }
}
```

### 2. Tool Updates

#### 2.1 Update plan_workout Tool in ToolProcessor
```swift
// In ToolProcessor.swift
case "plan_workout":
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let workoutParam = toolCall.parameters["workout"] as? String ?? ""
    let notesParam = toolCall.parameters["notes"] as? String
    let iconParam = toolCall.parameters["icon"] as? String  // NEW
    let result = try await executePlanWorkout(
        date: dateParam, 
        workout: workoutParam, 
        notes: notesParam,
        icon: iconParam  // NEW
    )
    return ToolCallResult(toolName: toolCall.name, result: result)

// Update the executePlanWorkout function
private func executePlanWorkout(
    date: String, 
    workout: String, 
    notes: String?,
    icon: String?  // NEW parameter
) async throws -> String {
    // ... existing date parsing logic ...
    
    if manager.planWorkout(
        for: targetDate, 
        workout: workout, 
        notes: notes,
        icon: icon  // Pass icon to manager
    ) {
        // ... success response ...
    }
}
```

#### 2.2 Update TrainingScheduleManager
```swift
// In TrainingScheduleManager.swift
func planWorkout(
    for date: Date, 
    workout: String, 
    notes: String?,
    icon: String? = nil  // NEW parameter
) -> Bool {
    // ... existing logic ...
    
    updatedDay.plannedWorkout = workout
    updatedDay.coachNotes = notes
    updatedDay.workoutIcon = icon  // Store the coach-selected icon
    updatedDay.lastModified = Date.current
    updatedDay.isCoachPlanned = true
    
    // ... rest of method ...
}
```

### 3. UI Updates

#### 3.1 Update DayCard View
```swift
// In WeeklyCalendarView.swift
struct DayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Text(day.dayOfWeek.shortName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.title3)
                .fontWeight(isToday || isSelected ? .bold : .medium)
            
            // Use coach-selected icon or show "no workout" indicator
            Image(systemName: workoutIcon)
                .font(.system(size: 20))
                .foregroundColor(workoutIconColor)
            
            // Keep existing status indicators if needed
        }
        // ... rest of view ...
    }
    
    private var workoutIcon: String {
        if let coachIcon = day.workoutIcon {
            // Coach explicitly selected an icon
            return coachIcon
        } else if day.plannedWorkout != nil {
            // Has workout but no icon specified - use generic
            return "figure.mixed.cardio"
        } else {
            // No workout planned
            return "calendar.badge.exclamationmark"
        }
    }
    
    private var workoutIconColor: Color {
        if day.plannedWorkout == nil {
            return .orange  // No workout planned
        } else {
            return .primary  // Has workout
        }
    }
}
```

#### 3.2 Update WorkoutDetailsCard 
```swift
// In WeeklyCalendarView.swift - WorkoutDetailsCard
// Update line 361 to use the new icon logic
Image(systemName: day.workoutIcon ?? "figure.mixed.cardio")
    .font(.title2)
    .foregroundColor(.blue)
```

### 4. System Prompt Updates

Add to SystemPrompt.md:

```markdown
## Workout Icon Selection

When planning workouts, you should specify an appropriate icon for each workout using the `icon` parameter:

[TOOL_CALL: plan_workout(
    date: "2025-09-10",
    workout: "60-minute steady state row at Zone 2",
    icon: "figure.rower"
)]

Available workout icons:
- "bed.double.fill" - Rest/recovery days
- "figure.rower" - Rowing workouts
- "bicycle" - Cycling/bike workouts
- "figure.run" - Running workouts  
- "figure.strengthtraining.traditional" - Strength/weight training
- "figure.yoga" - Yoga/mobility/stretching
- "figure.pool.swim" - Swimming workouts
- "figure.mixed.cardio" - Cross-training/mixed workouts
- "heart.fill" - Active recovery
- "chart.line.uptrend.xyaxis" - Testing/assessment days

Always select the most appropriate icon based on the primary activity in the workout. If no icon is specified, a generic workout icon will be used.
```

### 5. Remove Old Icon Logic

Remove or comment out the `workoutIcon(for:)` function from the DayOfWeek enum since it's no longer needed:

```swift
// In TrainingCalendar.swift - DayOfWeek enum
// Remove or comment out lines 38-56 (the workoutIcon function)
```

## Summary

This implementation allows the coach to specify workout icons when planning workouts through the `plan_workout` tool. The calendar will display:
- Coach-selected icons when provided
- A generic workout icon for planned workouts without specified icons  
- A "no workout planned" indicator for empty days

The solution is straightforward and gives the coach full control over workout visualization without requiring complex auto-detection or UI selection features.