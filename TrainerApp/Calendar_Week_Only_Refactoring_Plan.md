# Calendar Week-Only Refactoring Plan

## Overview
Remove the week/month toggle in the calendar view and keep only the week view functionality. This simplifies the calendar interface and removes unused monthly view code.

## Current Implementation Analysis

### Files Affected:
1. **TrainerApp/TrainerApp/Views/CalendarView.swift** (442 lines)
   - Contains both weekly and monthly calendar views
   - Has view mode picker and state management
   - Includes deep link navigation logic

2. **TrainerApp/TrainerApp/Models/TrainingCalendar.swift**
   - Contains `CalendarViewMode` enum (lines 122-134)

3. **TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift**
   - Already functional and will be preserved

### Components to Remove:
1. `CalendarViewMode` enum
2. View mode picker UI
3. `MonthlyCalendarView` struct (lines 110-228)
4. `MonthDayCard` struct (lines 230-284)
5. `WorkoutDetailSheet` struct (lines 287-369)
6. View mode state variables and logic

## Implementation Steps

### Step 1: Remove CalendarViewMode Enum
**File**: `TrainerApp/TrainerApp/Models/TrainingCalendar.swift`
- Remove lines 121-134 (the entire `CalendarViewMode` enum)

### Step 2: Simplify CalendarView.swift
**File**: `TrainerApp/TrainerApp/Views/CalendarView.swift`

**Changes to make:**
1. **Remove state variables** (line 5):
   - Remove `@State private var viewMode: CalendarViewMode = .week`

2. **Remove view mode picker** (lines 14-21):
   - Remove the entire Picker section for view mode selection

3. **Replace switch statement** (lines 24-31):
   - Replace the Group/switch with direct `WeeklyCalendarView` embedding

4. **Remove unused view structs** (lines 110-442):
   - Remove `MonthlyCalendarView` struct
   - Remove `MonthDayCard` struct  
   - Remove `WorkoutDetailSheet` struct
   - Remove `ProgramSetupSheet` struct (keep this - it's still used)

5. **Clean up deep link navigation** (lines 91-93):
   - Remove the `viewMode = .week` assignment since there's no view mode anymore
   - Simplify the navigation logic

### Step 3: Update Navigation Logic
**File**: `TrainerApp/TrainerApp/Views/CalendarView.swift`

**Deep link navigation simplification:**
- Remove view mode switching logic
- Keep the target date handling but simplify since we only have week view
- Remove the conditional check for finding target in current week vs passing to WeeklyCalendarView

### Step 4: Verify Dependencies
**Files to check for references:**
- Search entire codebase for `CalendarViewMode` references
- Search for `MonthlyCalendarView` references
- Search for `.month` view mode references

### Step 5: Test Build and Functionality
- Ensure the project builds without errors
- Verify calendar navigation still works
- Test deep link navigation to specific workout dates
- Verify program setup still functions

## Expected Outcome

### Before:
```swift
struct CalendarView: View {
    @State private var viewMode: CalendarViewMode = .week
    // ... picker UI ...
    switch viewMode {
    case .week:
        WeeklyCalendarView(scheduleManager: scheduleManager)
    case .month:
        MonthlyCalendarView(scheduleManager: scheduleManager)
    }
}
```

### After:
```swift
struct CalendarView: View {
    // ... simplified without view mode state ...
    WeeklyCalendarView(scheduleManager: scheduleManager)
}
```

## Benefits
1. **Simplified UI**: Remove unnecessary complexity from calendar interface
2. **Reduced codebase**: Remove ~300 lines of unused monthly view code
3. **Better focus**: Week view is more appropriate for daily workout planning
4. **Easier maintenance**: Fewer components to maintain and test

## Risk Assessment
- **Low risk**: WeeklyCalendarView is already fully functional
- **No data loss**: Only removing UI components, not data models
- **Easy rollback**: Changes are isolated and reversible

## Files to Modify Summary
1. `TrainerApp/TrainerApp/Models/TrainingCalendar.swift` - Remove enum
2. `TrainerApp/TrainerApp/Views/CalendarView.swift` - Major simplification
3. No changes needed to `WeeklyCalendarView.swift` - it stays as-is

## Testing Checklist
- [ ] Project builds successfully
- [ ] Calendar opens and displays current week
- [ ] Week navigation (previous/next) works
- [ ] Workout day selection works
- [ ] Deep link navigation to specific dates works
- [ ] Program setup functionality works
- [ ] No compiler warnings or errors