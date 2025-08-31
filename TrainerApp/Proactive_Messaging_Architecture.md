# Proactive Messaging Architecture for Rowing Coach Agent

## Overview
Transform the reactive chat-based rowing coach into a proactive training companion that intelligently reminds users based on their workout patterns and provides weekly progress summaries.

## Key Components

### 1. Workout Pattern Analyzer
```swift
class WorkoutPatternAnalyzer {
    // Analyzes historical workout completion times
    func analyzeWorkoutPatterns() -> WorkoutTimePattern {
        // Look at last 4 weeks of completed workouts
        // Identify most common workout times per day
        // Account for weekday vs weekend differences
    }
    
    struct WorkoutTimePattern {
        let typicalTimesByDay: [DayOfWeek: DateComponents]
        let consistency: Double // 0-1 score
        let preferredWindow: TimeWindow // e.g., morning/evening
    }
}
```

### 2. Smart Notification Scheduler
```swift
class SmartNotificationScheduler {
    // Core scheduling logic
    func scheduleSmartReminders() {
        // Pre-workout reminder (30-60 min before typical time)
        // Post-workout check-in (2 hours after typical time)
        // Sunday weekly review (consistent time)
    }
    
    // Contextual awareness
    func shouldSendReminder(for day: Date) -> Bool {
        // Check if workout already completed
        // Check if it's a rest day (Monday)
        // Check if user marked as traveling/sick
        // Check last interaction time
    }
}
```

### 3. Message Types and Templates

#### Pre-Workout Reminder
- **Trigger**: 30-60 minutes before typical workout time
- **Conditions**: Workout not yet completed, not a rest day
- **Content**: Today's planned workout, brief motivation, weather-aware adjustments

#### Post-Workout Check-in
- **Trigger**: 2 hours after typical workout time if not logged
- **Conditions**: Workout planned but not marked complete
- **Content**: Quick check if workout was done, option to log or reschedule

#### Sunday Weekly Review
- **Trigger**: Sunday evening (user-configurable time)
- **Content**: 
  - Week's training summary (X/Y workouts completed)
  - Progress metrics (weight, body composition trends)
  - Upcoming week preview
  - Achievements and areas for improvement

### 4. Notification Infrastructure

```swift
// Local notifications for reminders
class NotificationManager {
    func scheduleWorkoutReminder(at time: Date, workout: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Train! 💪"
        content.body = workout
        content.categoryIdentifier = "WORKOUT_REMINDER"
        
        // Interactive actions
        content.userInfo = ["type": "workout_reminder"]
    }
}

// Background refresh for updating schedules
class BackgroundTaskManager {
    func scheduleBackgroundRefresh() {
        // Daily at 3 AM: Analyze patterns, update reminder times
        // After each workout: Adjust future reminders
    }
}
```

### 5. User Preferences System

```swift
struct ProactiveMessagingPreferences {
    var enableSmartReminders: Bool = true
    var reminderLeadTime: TimeInterval = 45 * 60 // 45 minutes
    var sundayReviewTime: DateComponents = DateComponents(hour: 19, minute: 0)
    var quietHours: DateInterval? // Don't notify during these hours
    var vacationMode: Bool = false
}
```

### 6. Intelligent Message Suppression

```swift
class MessageSuppressor {
    func shouldSuppressMessage(type: MessageType) -> Bool {
        // Suppress if:
        // - User opened app in last 30 minutes
        // - Already sent similar message today
        // - User is in quiet hours
        // - Vacation mode is on
        // - Workout already logged
    }
}
```

## Implementation Strategy

### Phase 1: Basic Scheduled Reminders
1. Add notification permissions request
2. Implement fixed-time daily reminders
3. Add Sunday weekly review
4. Create notification action handlers

### Phase 2: Smart Timing
1. Build workout pattern analyzer
2. Implement adaptive reminder scheduling
3. Add post-workout check-ins
4. Create contextual awareness

### Phase 3: Advanced Features
1. Weather-based adjustments
2. Progress milestone celebrations
3. Streak tracking and motivation
4. Integration with calendar

## Message Examples

### Smart Pre-Workout Reminder
"Good morning! Based on your usual Tuesday routine, it's almost time for your Upper Body session. Today's plan: Floor press 4×6, Pendlay Row 4×6, Pull-ups AMRAP. Weather looks good for the 30-40' UT2 row afterward. 🚣‍♂️"

### Post-Workout Check-in
"Hey! Did you complete today's workout? Quick tap to log it, or let me know if you need to adjust the schedule."

### Sunday Weekly Review
"Week 3 Summary 📊
✅ 5/6 workouts completed (great consistency!)
📈 Weight: 169.5 lbs (↑0.8 from last week)
💪 Best session: Thursday's threshold rows
📅 Next week: Starting Week 4 of Aerobic Capacity

Keep up the excellent work! Rest well tomorrow."

## Technical Considerations

1. **Battery Optimization**: Use iOS background task scheduling efficiently
2. **Privacy**: All pattern analysis happens on-device
3. **Flexibility**: Easy to pause/resume notifications
4. **Sync**: Coordinate with iCloud to maintain consistency across devices
5. **Fallback**: If patterns unclear, use sensible defaults

## Success Metrics
- Workout completion rate improvement
- User engagement with notifications
- Reduced need for user-initiated check-ins
- Positive feedback on timing accuracy