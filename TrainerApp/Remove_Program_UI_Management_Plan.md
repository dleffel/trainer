# Remove Program UI Management Plan

## Overview
Remove all UI flows that allow users to start programs or update program settings. Only the trainer should perform these actions through tool calls, not through the user interface.

## Current Implementation Analysis

### Files Affected:
1. **TrainerApp/TrainerApp/Views/CalendarView.swift** (149 lines)
   - Contains toolbar menu with program setup/settings options
   - Has `ProgramSetupSheet` for program management
   - Auto-shows program setup when no program exists
   - Contains state management for sheet presentation

### Components to Remove:
1. **Toolbar Menu** (lines 27-53):
   - "Start New Program" button
   - "Program Settings" button  
   - "Schedule Race" button (placeholder)
   - Entire ellipsis menu

2. **ProgramSetupSheet** (lines 78-149):
   - Date picker for program start date
   - Program information display
   - Start/Update functionality
   - All associated UI components

3. **Auto-show Logic** (lines 62-64):
   - Automatic program setup presentation
   - Check for program existence

4. **State Variables**:
   - `@State private var showingProgramSetup`
   - Associated sheet presentation logic

## Implementation Steps

### Step 1: Remove Toolbar Menu
**File**: `TrainerApp/TrainerApp/Views/CalendarView.swift`
- Remove the entire toolbar menu (lines 27-53)
- Keep only the "Close" button in the leading position
- Remove the trailing toolbar item completely

### Step 2: Remove Program Setup Sheet
**File**: `TrainerApp/TrainerApp/Views/CalendarView.swift`
- Remove state variable `@State private var showingProgramSetup = false` (line 5)
- Remove sheet presentation `.sheet(isPresented: $showingProgramSetup)` (lines 55-57)
- Remove entire `ProgramSetupSheet` struct (lines 78-149)

### Step 3: Remove Auto-show Logic
**File**: `TrainerApp/TrainerApp/Views/CalendarView.swift`
- Remove program existence check and auto-show logic (lines 62-64)
- Keep deep link navigation logic intact
- Simplify `.onAppear` method

### Step 4: Clean Up Imports and Dependencies
- Verify no unused imports remain
- Check for any other references to removed components

## Expected Outcome

### Before:
```swift
struct CalendarView: View {
    @State private var showingProgramSetup = false
    // ... toolbar with program menu ...
    .sheet(isPresented: $showingProgramSetup) {
        ProgramSetupSheet(scheduleManager: scheduleManager)
    }
    // ... auto-show program setup logic ...
}

struct ProgramSetupSheet: View { /* 70 lines of UI */ }
```

### After:
```swift
struct CalendarView: View {
    // ... simplified toolbar with only Close button ...
    // ... no program setup UI ...
    // ... simplified onAppear without auto-show logic ...
}
// ProgramSetupSheet completely removed
```

## Benefits
1. **Cleaner UI**: Remove complex program management interface
2. **Clear Separation**: Only trainer controls program lifecycle via tools
3. **Simplified Code**: Remove ~80 lines of UI management code
4. **Better UX**: No confusing auto-popups or settings menus
5. **Tool-focused**: Aligns with trainer-controlled program management

## Risk Assessment
- **Low risk**: Program management functionality remains in TrainingScheduleManager
- **No data loss**: Only removing UI, not underlying program management
- **Easy rollback**: Changes are isolated to CalendarView

## Behavior Changes
1. **No automatic program setup**: Calendar will show empty state if no program exists
2. **No manual program controls**: Users cannot start/modify programs through UI
3. **Trainer-only control**: All program management happens via tool calls
4. **Simplified navigation**: Calendar focuses purely on viewing/navigating workouts

## Testing Checklist
- [ ] Calendar opens without program setup popup
- [ ] No toolbar menu for program management
- [ ] Calendar displays properly with existing programs
- [ ] Calendar displays properly with no program (empty state)
- [ ] Deep link navigation still works
- [ ] Project builds without errors
- [ ] No unused imports or references remain

## Tool Call Verification
Confirm these trainer tool calls still work:
- `start_training_program()` - Creates new programs
- `plan_workout()` - Plans individual workouts
- Program modification tools (if any)

This ensures complete separation between UI (viewing only) and program management (trainer tools only).