# Time Simulation Testing Guide

## Overview
A comprehensive time simulation system has been implemented to enable thorough testing of all date-dependent features in the TrainerApp without waiting for real time to pass.

## Implementation Details

### Core Components

1. **DateProvider Singleton** (`TrainerApp/Utilities/DateProvider.swift`)
   - Central manager for time simulation
   - Provides `currentDate` that returns either real or simulated time
   - Persists settings in UserDefaults

2. **Date Extension** 
   - `Date.current` - Replaces all `Date()` calls for testable time
   - `Date.realTime` - Available for logging actual timestamps

3. **SimpleDeveloperTimeControl UI** (`TrainerApp/Debug/SimpleDeveloperTimeControl.swift`)
   - Accessible from Developer Options menu
   - Enable/disable test mode
   - Jump to specific training weeks
   - Advance time by hours/days

### Modified Files
The following core files have been updated to use `Date.current` instead of `Date()`:

- **TrainingScheduleManager.swift** (13 replacements)
  - Workout scheduling
  - Date calculations for training blocks
  - Progress tracking

- **ToolProcessor.swift** (6 replacements)  
  - Workout data persistence
  - Timestamp generation

- **TrainingBlock.swift** (5 replacements)
  - Block progress calculations
  - Week/day determination

- **CalendarView.swift** (3 replacements)
  - Calendar display
  - Current date highlighting

- **WeeklyCalendarView.swift** (3 replacements)
  - Weekly view updates
  - Date navigation

## How to Use

### Accessing Time Controls

1. Open the app
2. Navigate to Developer Options (gear icon)
3. Select "Time Control"

### Testing Scenarios

#### 1. Testing Different Training Weeks
```
1. Enable "Test Mode" toggle
2. Use "Jump to Week" buttons:
   - Week 1 (Adaptation)
   - Week 5 (Build)
   - Week 9 (Peak)
   - Week 13 (Taper)
3. Observe how UI updates for each phase
```

#### 2. Testing Day-to-Day Progression
```
1. Enable Test Mode
2. Use "Advance 1 Day" button
3. Check:
   - Workout schedule updates
   - Calendar highlights
   - Progress tracking
```

#### 3. Testing Workout Completion Across Days
```
1. Start on a workout day
2. Complete partial workout
3. Advance time by 1 day
4. Verify workout data persists
5. Check if new day's workout is available
```

#### 4. Testing Week Transitions
```
1. Jump to end of week (e.g., Day 6 of Week 3)
2. Advance 1-2 days to cross week boundary
3. Verify:
   - New week loads correctly
   - Previous week's data is retained
   - Progress metrics update
```

#### 5. Testing Training Phase Transitions
```
1. Jump to last day of a phase
2. Advance to next phase
3. Verify phase-specific changes:
   - Workout intensities
   - Volume adjustments
   - UI theme changes
```

### Advanced Testing

#### Rapid Multi-Week Testing
```
1. Enable Test Mode
2. Start at Week 1
3. For each week:
   - Complete 1-2 workouts
   - Advance 7 days
   - Verify data persistence
4. Jump back to Week 1
5. Verify all data remains intact
```

#### Edge Case Testing
- **Past Dates**: Set time before training start
- **Future Dates**: Jump beyond 16-week program
- **Mid-Workout**: Start workout, advance time, resume
- **Timezone Changes**: Test with different system timezones

## Important Notes

### Data Persistence
- Workout data is keyed by date (workout_YYYY-MM-DD)
- Simulated dates create real data entries
- Data persists even when switching between test/real mode

### Known Limitations
1. Push notifications still use real time
2. HealthKit integration uses real timestamps
3. Some third-party integrations may use system time

### Debugging Tips
1. Check current mode: Look for "TEST MODE" indicator
2. Reset to real time: Disable test mode toggle
3. View actual date: Check device status bar
4. Clear test data: Use Export Options > Clear All Data

## Best Practices

1. **Always test in Test Mode first** before real-world testing
2. **Document test scenarios** with specific dates/times
3. **Verify data persistence** after time jumps
4. **Test boundary conditions** (week/phase transitions)
5. **Reset between test runs** for consistent results

## Troubleshooting

### Issue: Time doesn't advance
- Solution: Ensure Test Mode is enabled
- Check DateProvider.shared.isTestMode

### Issue: Workouts show wrong dates
- Solution: Clear app data and restart
- Verify Date.current is used everywhere

### Issue: Calendar highlights wrong day
- Solution: Force refresh calendar view
- Check timezone settings

## Testing Checklist

- [ ] All Date() calls replaced with Date.current
- [ ] Test mode toggle works
- [ ] Week jumping works correctly
- [ ] Day advancement updates UI
- [ ] Hour advancement for intra-day testing
- [ ] Data persists across time changes
- [ ] Real mode restores current time
- [ ] Calendar reflects simulated time
- [ ] Workouts load for simulated dates
- [ ] Progress calculations use simulated time

## Summary

This time simulation system enables comprehensive testing of all temporal aspects of the TrainerApp without waiting for real time to pass. It's particularly useful for:

1. QA testing full training cycles
2. Debugging date-specific issues  
3. Demonstrating app features
4. Accelerated user testing
5. Edge case validation

The implementation is clean, maintainable, and can be easily toggled on/off without affecting production behavior.