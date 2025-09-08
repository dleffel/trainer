# Context-Aware Workout Generation Implementation Plan

## Overview
This plan focuses on making the workout planning process inherently aware of the current training phase by modifying the underlying tools and data flow, ensuring that every workout planned automatically considers the macro cycle context.

## Core Concept
Instead of relying on the coach AI to remember to check the training phase, we'll build phase awareness directly into the workout planning tools. Every time a workout is planned, the system will:
1. Automatically retrieve the current training block
2. Include phase context in the workout data
3. Provide phase-specific guidance to the coach
4. Store phase metadata with each workout

## Implementation Details

### Phase 1: Enhance Tool Responses with Context

#### 1.1 Modify `executePlanWorkout` in ToolProcessor
```swift
private func executePlanWorkout(date: String, workout: String, notes: String?) async throws -> String {
    // ... existing code ...
    
    // NEW: Get current block context
    let currentBlock = manager.currentBlock
    let weekInBlock = manager.currentWeek
    let blockContext = generateBlockContext(currentBlock, weekInBlock)
    
    // NEW: Enhance workout with phase metadata
    let enhancedWorkout = "\(workout)\n[Phase: \(currentBlock?.type.rawValue ?? "Unknown") - Week \(weekInBlock)]"
    
    // Save with enhanced context
    if manager.planSingleWorkout(for: targetDate, workout: enhancedWorkout, notes: notes) {
        return """
        [Workout Planned - \(currentBlock?.type.rawValue ?? "Unknown") Block]
        • Date: \(dateStr)
        • Training Phase: \(currentBlock?.type.rawValue ?? "Unknown") (Week \(weekInBlock) of \(currentBlock?.type.duration ?? 0))
        • Workout: \(workout)
        • Phase Focus: \(blockContext.focus)
        • Recommended Intensity: \(blockContext.intensity)
        \(notes != nil ? "• Notes: \(notes!)" : "")
        • Status: Saved to calendar
        """
    }
}
```

#### 1.2 Add Block Context Generator
```swift
struct BlockContext {
    let focus: String
    let intensity: String
    let volumeGuideline: String
    let suggestedExercises: [String]
}

private func generateBlockContext(_ block: TrainingBlock?, _ weekInBlock: Int) -> BlockContext {
    guard let block = block else {
        return BlockContext(
            focus: "General fitness",
            intensity: "Moderate",
            volumeGuideline: "Standard volume",
            suggestedExercises: []
        )
    }
    
    switch block.type {
    case .hypertrophyStrength:
        return BlockContext(
            focus: "Building muscle and strength",
            intensity: weekInBlock <= 3 ? "Moderate (70-80%)" : "High (80-90%)",
            volumeGuideline: "3-5 sets, 3-8 reps for main lifts",
            suggestedExercises: ["Squats", "Deadlifts", "Bench Press", "Rows", "Pull-ups"]
        )
        
    case .aerobicCapacity:
        return BlockContext(
            focus: "Building endurance base",
            intensity: "Zone 2 (135-145 HR)",
            volumeGuideline: "45-75 minutes continuous",
            suggestedExercises: ["Steady Row", "Long Bike", "Zone 2 Run", "Mixed Cardio"]
        )
        
    case .deload:
        return BlockContext(
            focus: "Recovery and adaptation",
            intensity: "Light (50-70% of normal)",
            volumeGuideline: "30% volume reduction",
            suggestedExercises: ["Light Row", "Mobility Work", "Yoga", "Easy Bike", "Walking"]
        )
        
    default:
        return BlockContext(
            focus: block.type.rawValue,
            intensity: "Varies",
            volumeGuideline: "Program specific",
            suggestedExercises: []
        )
    }
}
```

### Phase 2: Enhanced Training Status Response

#### 2.1 Improve `executeGetTrainingStatus` Output
```swift
private func executeGetTrainingStatus() async throws -> String {
    // ... existing code ...
    
    let blockContext = generateBlockContext(block, week)
    let nextWorkoutGuidance = generateNextWorkoutGuidance(block, week, manager.currentDay)
    
    return """
    [Training Status]
    • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
    • Overall Progress: Week \(totalWeek) of 20
    • Today: \(day.name)
    
    [Current Phase Guidelines]
    • Focus: \(blockContext.focus)
    • Intensity: \(blockContext.intensity)
    • Volume: \(blockContext.volumeGuideline)
    • Key Exercises: \(blockContext.suggestedExercises.joined(separator: ", "))
    
    [Today's Workout Should Be]
    \(nextWorkoutGuidance)
    
    Use [TOOL_CALL: plan_workout] to schedule today's phase-appropriate workout.
    """
}
```

#### 2.2 Add Smart Workout Suggestions
```swift
private func generateNextWorkoutGuidance(
    _ block: TrainingBlock?, 
    _ weekInBlock: Int, 
    _ dayOfWeek: DayOfWeek
) -> String {
    guard let block = block else {
        return "Plan based on athlete's current fitness level"
    }
    
    // Generate day and phase-specific guidance
    switch (block.type, dayOfWeek) {
    case (.hypertrophyStrength, .tuesday):
        return "Lower body strength day: Squats or Deadlifts as main lift (3-5 reps @ 80-85%), followed by accessory work"
        
    case (.hypertrophyStrength, .thursday):
        return "Upper body strength day: Bench or Press as main lift (3-5 reps @ 80-85%), plus pulling movements"
        
    case (.hypertrophyStrength, .friday):
        return "Full body volume day: Higher reps (8-12) at moderate intensity (65-75%)"
        
    case (.hypertrophyStrength, .saturday), (.hypertrophyStrength, .sunday):
        return "Mixed training: Combine strength work with conditioning or sport-specific practice"
        
    case (.aerobicCapacity, .tuesday):
        return "Long aerobic session: 60-75 min steady row or bike at Zone 2 (HR 135-145)"
        
    case (.aerobicCapacity, .thursday):
        return "Tempo intervals: 3-4 x 10-15 min at threshold pace with 3-5 min recovery"
        
    case (.aerobicCapacity, .friday):
        return "Mixed cardio: 45-60 min combining different modalities (row/bike/run)"
        
    case (.aerobicCapacity, .saturday), (.aerobicCapacity, .sunday):
        return "Long endurance: 75-90+ min at comfortable aerobic pace, can split into 2 sessions"
        
    case (.deload, _):
        let normalDay = generateNextWorkoutGuidance(
            TrainingBlock(type: weekInBlock < 11 ? .hypertrophyStrength : .aerobicCapacity, 
                         startDate: block.startDate, 
                         endDate: block.endDate, 
                         weekNumber: block.weekNumber),
            weekInBlock,
            dayOfWeek
        )
        return "DELOAD WEEK: \(normalDay) but reduce volume by 30% and intensity to 70% of normal"
        
    default:
        return "Rest day or active recovery as planned"
    }
}
```

### Phase 3: Workout Storage Enhancement

#### 3.1 Update WorkoutDay Model
```swift
// In TrainingCalendar.swift
struct WorkoutDay: Codable, Identifiable {
    // ... existing properties ...
    
    // NEW: Phase tracking
    var plannedBlockType: BlockType?
    var weekInBlock: Int?
    var phaseContext: String?
    var intensityLevel: String?
    var volumeTarget: String?
}
```

#### 3.2 Modify Save Method in TrainingScheduleManager
```swift
func planSingleWorkout(for date: Date, workout: String, notes: String?) -> Bool {
    // ... existing code ...
    
    // NEW: Capture phase context at save time
    let currentBlock = self.currentBlock
    let weekInBlock = self.currentWeek
    
    workoutDay.plannedWorkout = workout
    workoutDay.isCoachPlanned = true
    workoutDay.plannedBlockType = currentBlock?.type
    workoutDay.weekInBlock = weekInBlock
    workoutDay.phaseContext = "\(currentBlock?.type.rawValue ?? "") - Week \(weekInBlock)"
    
    // ... rest of save logic ...
}
```

### Phase 4: Validation and Warnings

#### 4.1 Add Phase Mismatch Detection
```swift
private func detectPhaseMismatch(workout: String, blockType: BlockType) -> String? {
    let workoutLower = workout.lowercased()
    
    switch blockType {
    case .hypertrophyStrength:
        // Check for inappropriate endurance focus during strength phase
        if workoutLower.contains("zone 2") || 
           workoutLower.contains("steady state") ||
           workoutLower.contains("60 min") ||
           workoutLower.contains("70 min") {
            return "⚠️ Note: This appears to be an endurance-focused workout during a Strength block. Consider strength training instead."
        }
        
    case .aerobicCapacity:
        // Check for inappropriate strength focus during aerobic phase
        if workoutLower.contains("heavy") || 
           workoutLower.contains("3x5") ||
           workoutLower.contains("max") ||
           workoutLower.contains("1rm") {
            return "⚠️ Note: This appears to be strength-focused during an Aerobic block. Consider endurance training instead."
        }
        
    case .deload:
        // Check for excessive volume during deload
        if !workoutLower.contains("easy") && 
           !workoutLower.contains("light") &&
           !workoutLower.contains("recovery") {
            return "⚠️ Remember: This is a deload week. Reduce volume by 30% and keep intensity moderate."
        }
        
    default:
        break
    }
    
    return nil
}
```

#### 4.2 Include Warnings in Tool Response
```swift
private func executePlanWorkout(date: String, workout: String, notes: String?) async throws -> String {
    // ... existing code ...
    
    // Check for phase mismatch
    let warning = detectPhaseMismatch(workout, currentBlock?.type ?? .hypertrophyStrength)
    
    if manager.planSingleWorkout(for: targetDate, workout: enhancedWorkout, notes: notes) {
        return """
        [Workout Planned - \(currentBlock?.type.rawValue ?? "Unknown") Block]
        • Date: \(dateStr)
        • Training Phase: \(currentBlock?.type.rawValue ?? "Unknown") (Week \(weekInBlock) of \(currentBlock?.type.duration ?? 0))
        • Workout: \(workout)
        \(warning != nil ? "\n\(warning!)\n" : "")
        • Phase Focus: \(blockContext.focus)
        • Status: Saved to calendar
        """
    }
}
```

### Phase 5: System Prompt Minimal Updates

Add just this key instruction to SystemPrompt.md:
```markdown
## CRITICAL: Phase-Aware Planning

The system will automatically provide phase context when you check training status or plan workouts. ALWAYS:
1. Check [TOOL_CALL: get_training_status] before planning - it now includes phase-specific guidance
2. Follow the "Today's Workout Should Be" recommendation
3. The tool will warn you if workouts don't match the current phase
```

## Implementation Benefits

### Automatic Phase Awareness
- Every workout planned includes phase context automatically
- No reliance on AI memory or prompt following
- Phase information is embedded in the data flow

### Smart Guidance
- Tools provide specific workout suggestions based on current phase and day
- Warnings when workouts don't match expected patterns
- Progressive recommendations based on week within block

### Data Persistence
- Phase context saved with every workout
- Historical tracking of which phase each workout belonged to
- Can analyze phase-appropriate compliance over time

### Minimal AI Dependency
- System enforces phase awareness rather than relying on prompt
- Tools guide the coach toward appropriate workouts
- Validation catches mismatches

## Testing Strategy

1. **Phase Transition Testing**
   - Test workout planning at week 10 (end of strength)
   - Test at week 11 (deload)
   - Test at week 12 (start of aerobic)

2. **Mismatch Detection**
   - Plan endurance workout during strength phase
   - Plan heavy lifting during aerobic phase
   - Plan normal volume during deload

3. **Context Verification**
   - Verify phase metadata saves with workouts
   - Check that get_training_status provides guidance
   - Confirm warnings appear for mismatched workouts

## Implementation Timeline

### Day 1: Core Tool Enhancement
- Update executePlanWorkout with phase context
- Add block context generator
- Implement enhanced training status

### Day 2: Workout Guidance System
- Create workout suggestion logic
- Add day-specific recommendations
- Integrate with get_training_status

### Day 3: Validation Layer
- Implement phase mismatch detection
- Add warning system
- Update tool responses

### Day 4: Testing & Refinement
- Test all phase transitions
- Verify guidance accuracy
- Fine-tune recommendations

## Success Criteria

1. **Every workout includes phase context** in the saved data
2. **Get_training_status provides specific guidance** for the current day
3. **Warnings appear** when workouts don't match phase
4. **Coach naturally follows phase** due to tool guidance
5. **No prompt engineering required** - system handles it

This approach makes phase awareness systematic rather than dependent on AI behavior, ensuring consistent phase-appropriate workout planning.