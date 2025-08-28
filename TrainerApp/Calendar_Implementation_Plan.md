# Training Calendar Implementation Plan

## Overview
Add a calendar feature to the TrainerApp that tracks training blocks, weeks, and days. This will help both the AI coach and athlete understand where they are in the training cycle.

## Key Requirements

### 1. Training Block Tracking
- Display current training block (Aerobic-Capacity, Hypertrophy-Strength, Deload, Race-Prep)
- Show week number within current block (e.g., "Week 3 of 8")
- Track overall macro-cycle progress (which of the 4 macro-cycles)
- Store start date of training program

### 2. Calendar Display
- Weekly view showing which training day it is (Mon-Sun)
- Monthly view with block transitions clearly marked
- Visual indicators for:
  - Current day
  - Completed workouts
  - Upcoming sessions
  - Block transitions
  - Deload weeks

### 3. Data Storage
- Store in iCloud for persistence across devices
- Track:
  - Program start date
  - Current macro-cycle number (1-4)
  - Current block type
  - Current week within block
  - Workout completion status
  - Any race dates scheduled

### 4. User Interface Components

#### 4.1 Calendar Button
- Add calendar icon button to navigation bar (next to settings)
- Show current block/week info as badge or subtitle

#### 4.2 Calendar View
- **Header**: Current block name, week X of Y
- **Weekly View**: 
  - 7-day grid showing planned workouts
  - Highlight current day
  - Check marks for completed workouts
  - Tap to see workout details
- **Monthly View**:
  - Color-coded blocks
  - Block transition dates
  - Progress visualization

#### 4.3 Block Overview
- Summary card showing:
  - Total weeks in current block
  - Progress bar
  - Next block preview
  - Days until next deload

### 5. Integration Points

#### 5.1 With AI Coach
- Coach can query current position in training cycle
- Automatically generate appropriate workouts for current block/week
- Remind about upcoming deload weeks
- Adjust recommendations based on missed workouts

#### 5.2 With Existing Data
- Link to workout history
- Show completion rates
- Track adherence to program

### 6. Technical Implementation

#### 6.1 New Files to Create
- `Models/TrainingCalendar.swift` - Core calendar data model
- `Models/TrainingBlock.swift` - Block type definitions
- `Views/CalendarView.swift` - Main calendar UI
- `Views/CalendarButton.swift` - Navigation bar button
- `Views/WeeklyCalendarView.swift` - Weekly workout grid
- `Views/MonthlyCalendarView.swift` - Monthly overview
- `Managers/TrainingScheduleManager.swift` - Business logic

#### 6.2 Data Model
```swift
struct TrainingProgram {
    let startDate: Date
    var currentMacroCycle: Int (1-4)
    var raceDate: Date? // Optional
}

struct TrainingBlock {
    let type: BlockType
    let duration: Int // weeks
    let startWeek: Int // within macro-cycle
}

enum BlockType {
    case aerobicCapacity
    case hypertrophyStrength  
    case deload
    case racePrep
    case taper
}

struct WorkoutDay {
    let date: Date
    let dayType: DayOfWeek
    let plannedWorkout: String?
    var completed: Bool
    var notes: String?
}
```

#### 6.3 Key Functions
- Calculate current block from start date
- Determine week within block
- Generate calendar data for any date range
- Mark workout completion
- Handle race date insertion and schedule adjustment

### 7. Visual Design
- Use system calendar styling for familiarity
- Color scheme:
  - Aerobic blocks: Blue
  - Hypertrophy-Strength: Orange
  - Deload: Green
  - Race-Prep: Red
  - Current day: Highlighted border
- Icons for workout types (rowing, strength, rest)

### 8. Implementation Priority
1. Core data model and calculations
2. Basic weekly view with current position
3. Workout completion tracking
4. Monthly overview
5. Race date scheduling
6. Historical view and statistics

### 9. Testing Considerations
- Test block transitions
- Test with different start dates
- Verify calculations across year boundaries
- Test race date insertion logic
- Ensure iCloud sync works properly

### 10. Future Enhancements
- Export calendar to Apple Calendar
- Push notifications for workouts
- Integration with HealthKit workout data
- Progress photos linked to calendar dates
- Performance metrics overlay on calendar