# Fix Calendar Views to Respect DateProvider Date

## Problem
The calendar views (WeeklyCalendarView and MonthlyCalendarView) are highlighting the real current date instead of the DateProvider's simulated date when in developer test mode. This happens because they use `Calendar.isDateInToday()` which always checks against the system's real date.

## Root Cause Analysis
1. **WeeklyCalendarView.swift** (line 127):
   ```swift
   DayCard(day: day, isToday: calendar.isDateInToday(day.date))
   ```

2. **CalendarView.swift** (line 191 in MonthlyCalendarView):
   ```swift
   isToday: calendar.isDateInToday(day.date),
   ```

Both use `Calendar.isDateInToday()` which compares against the real system date, ignoring the DateProvider's simulated date.

## Solution
Replace `calendar.isDateInToday(day.date)` with `Calendar.current.isDate(day.date, inSameDayAs: Date.current)` in both locations.

This works because:
- `Date.current` is an extension that returns `DateProvider.shared.currentDate`
- When in test mode, this returns the simulated date
- When not in test mode, it returns the real date
- `Calendar.isDate(_:inSameDayAs:)` will properly compare the dates

## Implementation Steps

### 1. Fix WeeklyCalendarView.swift
**File:** `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift`
**Line:** 127

Change from:
```swift
DayCard(day: day, isToday: calendar.isDateInToday(day.date))
```

To:
```swift
DayCard(day: day, isToday: calendar.isDate(day.date, inSameDayAs: Date.current))
```

### 2. Fix CalendarView.swift (MonthlyCalendarView)
**File:** `TrainerApp/TrainerApp/Views/CalendarView.swift`
**Line:** 191

Change from:
```swift
isToday: calendar.isDateInToday(day.date),
```

To:
```swift
isToday: calendar.isDate(day.date, inSameDayAs: Date.current),
```

## Testing
After making these changes:
1. Enable test mode in Developer Settings
2. Set a different simulated date
3. Open the calendar view
4. Verify that the highlighted day matches the simulated date, not the real date
5. Switch between Week and Month views to ensure both work correctly

## Additional Considerations
- No other changes needed since `Date.current` already properly returns the simulated date
- The DateProvider extension is already in place and working
- This fix maintains backwards compatibility - when not in test mode, it behaves exactly the same as before