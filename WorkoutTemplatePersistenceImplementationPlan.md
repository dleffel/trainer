# Workout Template Persistence Implementation Plan

## Overview
Implement a system to pre-populate training schedules with specific workout types based on predefined training block rules, while maintaining the coach's ability to fill in exercise details.

## Current State Analysis

### Existing Architecture
- **TrainingScheduleManager**: Creates blank [`WorkoutDay`](TrainerApp/TrainerApp/Models/TrainingCalendar.swift:60) objects in [`generateWeek()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:193)
- **StructuredWorkout**: Sophisticated exercise modeling already in place
- **BlockType**: Pre-defined training blocks (hypertrophyStrength, aerobicCapacity, deload) with durations
- **Coach Integration**: Uses [`plan_workout`](TrainerApp/TrainerApp/SystemPrompt.md:131) tool calls to persist workouts

### Current Workflow
1. [`TrainingScheduleManager.generateWeek()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:193) creates blank [`WorkoutDay`](TrainerApp/TrainerApp/Models/TrainingCalendar.swift:60) objects
2. Coach uses tool calls to fill in specific exercises
3. [`StructuredWorkout`](TrainerApp/TrainerApp/Models/StructuredWorkout.swift:6) objects are created and persisted

## Proposed Implementation

### 1. Create Workout Template System

#### A. New Model: [`WorkoutTemplate`](TrainerApp/TrainerApp/Models/WorkoutTemplate.swift:1)
```swift
struct WorkoutTemplate: Codable {
    let title: String
    let summary: String
    let sessionType: WorkoutSessionType
    let modalityPrimary: String
    let modalitySecondary: String?
    let focus: String
    let durationMinutes: Int?
    let intensityZone: String?
    let icon: String
    let notes: String?
}

enum WorkoutSessionType: String, CaseIterable, Codable {
    case strength = "Strength"
    case cardio = "Cardio"  
    case mobility = "Mobility"
    case rest = "Rest"
    case mixed = "Mixed"
}
```

#### B. New Model: [`TrainingBlockTemplate`](TrainerApp/TrainerApp/Models/TrainingBlockTemplate.swift:1)
```swift
struct TrainingBlockTemplate: Codable {
    let blockType: BlockType
    let weeklyTemplate: [DayOfWeek: WorkoutTemplate]
    
    static let templates: [BlockType: TrainingBlockTemplate] = [
        .hypertrophyStrength: hypertrophyStrengthTemplate,
        .deload: deloadTemplate,
        .aerobicCapacity: aerobicCapacityTemplate
    ]
}
```

### 2. Define Training Block Templates

#### A. Hypertrophy-Strength Block (10 weeks)
```swift
private static let hypertrophyStrengthTemplate = TrainingBlockTemplate(
    blockType: .hypertrophyStrength,
    weeklyTemplate: [
        .monday: WorkoutTemplate(
            title: "Rest Day",
            summary: "Mobility + core (15–25′)",
            sessionType: .mobility,
            modalityPrimary: "mobility",
            modalitySecondary: nil,
            focus: "Tissue quality, hips/thoracic",
            durationMinutes: 20,
            intensityZone: "Recovery",
            icon: "figure.flexibility",
            notes: "Focus on hip and thoracic spine mobility"
        ),
        .tuesday: WorkoutTemplate(
            title: "Strength - Lower + Z2",
            summary: "Strength – Lower (squat/hinge) → 30–40′ Z2 bike or erg",
            sessionType: .mixed,
            modalityPrimary: "strength",
            modalitySecondary: "bike",
            focus: "Hypertrophy (legs); easy aerobic",
            durationMinutes: 90,
            intensityZone: "Strength + Z2",
            icon: "figure.strengthtraining.traditional",
            notes: "Squat/hinge movements followed by easy aerobic work"
        ),
        // ... continue for all 7 days
    ]
)
```

#### B. Deload Block Template
- Reduced volume versions (-30%) of main block types
- Focus on recovery and movement maintenance

#### C. Aerobic-Capacity Block Template  
- Higher intensity cardio focus
- Reduced strength volume (2×/week maintenance)

### 3. Update TrainingScheduleManager

#### A. Modify [`generateWeek()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:193)
```swift
func generateWeek(containing date: Date) -> [WorkoutDay] {
    // Existing logic to find target block...
    
    for dayOffset in 0..<7 {
        if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) {
            // Check for existing saved workout first (unchanged)
            if let existingWorkout = loadExistingWorkout(for: dayDate) {
                days.append(existingWorkout)
            } else {
                // NEW: Apply workout template for this block + day combination
                let workoutDay = createWorkoutDayWithTemplate(
                    date: dayDate, 
                    blockType: targetBlock.type
                )
                days.append(workoutDay)
            }
        }
    }
    
    return days
}
```

#### B. New Helper Method
```swift
private func createWorkoutDayWithTemplate(date: Date, blockType: BlockType) -> WorkoutDay {
    let dayOfWeek = DayOfWeek.from(date: date)
    
    // Get template for this block + day combination
    guard let blockTemplate = TrainingBlockTemplate.templates[blockType],
          let workoutTemplate = blockTemplate.weeklyTemplate[dayOfWeek] else {
        // Fallback to blank workout day
        return WorkoutDay(date: date, blockType: blockType)
    }
    
    // Create WorkoutDay with template-derived structured workout
    var workoutDay = WorkoutDay(date: date, blockType: blockType)
    workoutDay.structuredWorkout = createStructuredWorkoutFromTemplate(workoutTemplate)
    workoutDay.workoutIcon = workoutTemplate.icon
    workoutDay.isCoachPlanned = false // Template-generated, not coach-planned
    
    return workoutDay
}
```

#### C. Template to StructuredWorkout Conversion
```swift
private func createStructuredWorkoutFromTemplate(_ template: WorkoutTemplate) -> StructuredWorkout {
    // Create a skeleton StructuredWorkout with template info
    // Coach will fill in specific exercises later
    
    let placeholderExercise = Exercise(
        kind: template.modalityPrimary,
        name: template.summary,
        focus: template.focus,
        equipment: nil,
        tags: nil,
        detail: .generic(GenericDetail(
            items: ["Template placeholder - coach will add specific exercises"],
            notes: template.notes
        ))
    )
    
    return StructuredWorkout(
        title: template.title,
        summary: template.summary,
        durationMinutes: template.durationMinutes,
        notes: template.notes,
        exercises: [placeholderExercise]
    )
}
```

### 4. Preserve Coach Workflow

#### A. Template Override Capability
- When coach uses [`plan_workout`](TrainerApp/TrainerApp/SystemPrompt.md:131) tool, it completely replaces template
- Template serves as starting point/structure, not constraint

#### B. Template Metadata
- Add `isTemplateGenerated: Bool` to [`WorkoutDay`](TrainerApp/TrainerApp/Models/TrainingCalendar.swift:60)
- UI can differentiate between template and coach-created workouts

### 5. Implementation Phases

#### Phase 1: Core Template System
1. Create [`WorkoutTemplate`](TrainerApp/TrainerApp/Models/WorkoutTemplate.swift:1) and [`TrainingBlockTemplate`](TrainerApp/TrainerApp/Models/TrainingBlockTemplate.swift:1) models
2. Define template data for all three block types
3. Add template application logic to [`generateWeek()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:193)

#### Phase 2: Integration Testing
1. Test template application with existing calendar views
2. Verify coach tool calls still override templates properly
3. Test persistence and loading of template-generated workouts

#### Phase 3: UI Enhancement
1. Add visual indicators for template vs coach-planned workouts
2. Add "Reset to Template" functionality for coaches
3. Template preview in coach interface

### 6. Benefits

#### A. Structure and Guidance
- Athletes see structured weekly patterns immediately
- Clear progression through training blocks
- Consistent workout timing and focus

#### B. Coach Efficiency
- Starting templates reduce planning overhead
- Clear framework for exercise selection
- Maintains full customization flexibility

#### C. Program Integrity
- Ensures training block principles are followed
- Consistent volume and intensity patterns
- Automatic adaptation to deload periods

### 7. Technical Considerations

#### A. Backward Compatibility
- All existing [`WorkoutDay`](TrainerApp/TrainerApp/Models/TrainingCalendar.swift:60) objects continue to work
- Template system is additive, not breaking

#### B. Performance
- Templates are static data, no performance impact
- Template application only occurs for new dates

#### C. Customization
- Easy to modify templates for different athlete needs
- Potential for athlete-specific template variants

## Next Steps

1. **Review and Approve**: Does this plan meet your requirements?
2. **Implementation Priority**: Which aspects are most critical to implement first?
3. **Template Details**: Do you want to refine any specific workout templates?

This implementation will provide the structured, pre-populated workout types you requested while preserving the coach's ability to fill in specific exercises and make adjustments as needed.