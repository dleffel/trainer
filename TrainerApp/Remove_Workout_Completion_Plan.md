# Plan: Remove Workout Completion Tracking

## Overview
Remove all workout completion tracking functionality from the TrainerApp, simplifying the application by eliminating the ability to mark workouts as complete/incomplete.

## Files to Modify

### 1. ToolProcessor.swift
- **Remove**: `mark_workout_complete` case (lines 135-141)
- **Remove**: `executeMarkWorkoutComplete` method (lines 420-443)
- **Update**: Any references in status displays

### 2. TrainingCalendar.swift (WorkoutDay struct)
- **Remove**: `completed` field (line 157)
- **Remove**: `notes` field (line 158) - only used for completion notes
- **Remove**: `actualWorkout` field (line 159) - only used when marking complete

### 3. TrainingScheduleManager.swift
- **Remove**: `markWorkoutCompleted` method (lines 273-285)
- **Remove**: `markWorkoutIncomplete` method (lines 288-298)
- **Remove**: `saveWorkoutCompletion` method (lines 339-365)
- **Remove**: `loadWorkoutCompletions` method (lines 368-398)
- **Remove**: `toggleWorkoutCompletion` method (lines 574-579)
- **Remove**: Completion persistence logic from `updateWorkoutDay`
- **Remove**: `WorkoutCompletionData` struct
- **Clean up**: Any completion-related UserDefaults keys

### 4. WeeklyCalendarView.swift
- **Remove**: Completion checkmarks in DayCard (lines 226-229)
- **Remove**: Completion-based color logic in `workoutIconColor` (lines 262-268)
- **Remove**: Completion UI in WorkoutDetailSheet (lines 302-306, 326-354, 358-383)
- **Remove**: `markWorkoutCompleted`/`markWorkoutIncomplete` button actions
- **Remove**: `notes` and `actualWorkout` state variables
- **Simplify**: Display to only show planned workouts

### 5. CalendarView.swift
- **Remove**: Completion checkmarks (lines 245-250)
- **Remove**: Any completion-based styling

### 6. SystemPrompt.md
- **Remove**: `mark_workout_complete` tool documentation (section 14.5)
- **Remove**: All references to marking workouts complete in sections:
  - Section 0.4 (priority tools)
  - Section 9 (Daily Interaction Protocol)
  - Section 10 (Workout Completion)
  - Update examples that mention completion

### 7. ProactiveMessagingTypes.swift
- **Remove**: `workoutCompleted` field from `ProactiveContext`
- **Update**: Context description to remove completion status

### 8. ProactiveCoachManager.swift & ProactiveScheduler.swift
- **Remove**: `workoutCompleted` logic from context building
- **Remove**: `findLastWorkoutTime` method (no longer relevant)
- **Update**: Proactive messaging logic to not depend on completion status

## Implementation Order

1. **Start with data model** (TrainingCalendar.swift)
   - Remove fields from WorkoutDay struct

2. **Remove tool implementation** (ToolProcessor.swift)
   - Remove case and method

3. **Clean up manager** (TrainingScheduleManager.swift)
   - Remove all completion-related methods and persistence

4. **Update UI** (WeeklyCalendarView.swift, CalendarView.swift)
   - Remove completion indicators and controls
   - Simplify to display-only mode

5. **Update proactive messaging** (ProactiveMessagingTypes, ProactiveCoachManager, ProactiveScheduler)
   - Remove completion context

6. **Update documentation** (SystemPrompt.md)
   - Remove tool documentation and references

## Expected Simplifications

- **Cleaner UI**: Calendar will only show planned workouts without tracking status
- **Simpler data model**: WorkoutDay becomes read-only with just planned content
- **Reduced persistence**: No need to save/load completion data
- **Streamlined coach interactions**: Focus on planning rather than tracking

## Build & Test Strategy

1. Make all changes systematically
2. Compile after each major file change to catch errors early
3. Fix any cascade errors from removed fields/methods
4. Test that app still displays workout schedule correctly
5. Verify proactive messaging still works without completion context