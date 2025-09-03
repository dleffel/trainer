# Workout Instructions Persistence Debug

## Issue
The `generate_workout_instructions` tool is being called successfully, but the detailed instructions are not showing up in the calendar view when navigating to the workout day.

## Root Cause
The `TrainingScheduleManager` was not properly persisting the `detailedInstructions` field when loading saved workout days. The `loadWorkoutCompletions` method was only restoring `completed`, `notes`, and `actualWorkout` fields.

## Solution Applied

### 1. Updated TrainingScheduleManager.swift
Added persistence for the `detailedInstructions` field:

```swift
// In loadWorkoutCompletions method (line ~381)
days[index].detailedInstructions = savedDay.detailedInstructions
```

### 2. Added Debug Logging
Added comprehensive logging to track the save/load process:

```swift
// In updateWorkoutDay method
print("📝 TrainingScheduleManager: Updating workout day for \(dateKey(for: day.date))")
if let instructions = day.detailedInstructions {
    print("✅ TrainingScheduleManager: Has detailed instructions with \(instructions.sections.count) sections")
}

// In saveWorkoutCompletion method
print("💾 TrainingScheduleManager: Saving workout for key: \(key)")
if let instructions = day.detailedInstructions {
    print("✅ TrainingScheduleManager: Saving with \(instructions.sections.count) instruction sections")
}

// In loadWorkoutCompletions method
if let instructions = savedDay.detailedInstructions {
    print("✅ TrainingScheduleManager: Loaded \(instructions.sections.count) instruction sections")
}
```

## Testing Steps

1. **Ask the coach for workout instructions:**
   - "Can you give me detailed instructions for today's workout?"
   - Coach should call `generate_workout_instructions` tool

2. **Verify the save process:**
   - Check console logs for "Saving with X instruction sections"
   - Confirm the data is saved to UserDefaults/iCloud

3. **Click the deep link:**
   - Tap the `trainer://calendar/[date]` link in chat
   - Should navigate to the calendar view

4. **Verify the load process:**
   - Check console logs for "Loaded X instruction sections"
   - Detailed instructions card should appear in the workout detail sheet

## Expected Behavior

1. Coach generates instructions and returns a deep link
2. Instructions are saved to persistent storage
3. Clicking the link opens the calendar to the correct date
4. The workout detail sheet shows the detailed instructions card
5. Instructions card is auto-expanded when accessed via deep link

## Verification Points

- [ ] Tool is called by the coach
- [ ] Instructions are generated with multiple sections
- [ ] Save logs show instructions being persisted
- [ ] Deep link is tappable in chat
- [ ] Calendar opens to correct date
- [ ] Load logs show instructions being restored
- [ ] Instructions card is visible in detail sheet
- [ ] Instructions content matches what was generated

## Next Steps

If instructions still don't appear after these fixes:
1. Check if WorkoutDay model is properly encoding/decoding the detailedInstructions field
2. Verify iCloud sync is not overwriting local changes
3. Ensure the workout day being loaded matches the one that was saved (same date key)