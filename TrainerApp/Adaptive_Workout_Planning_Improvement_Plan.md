# Adaptive Workout Planning Improvement Plan

## Current Problem
The coach currently uses `plan_week_workouts` to plan an entire week of workouts upfront, which:
- Doesn't allow for adaptation based on workout performance
- Makes it difficult to modify plans after they're created
- Forces rigid weekly planning instead of day-by-day adaptation
- Lacks CRUD operations for individual workout management

## Proposed Solution
Transform the workout planning system from batch weekly planning to adaptive daily planning with full CRUD capabilities.

## 1. New Tool Architecture

### 1.1 Replace/Supplement Current Tools
Instead of just `plan_week_workouts`, introduce granular CRUD operations:

#### A. `plan_workout` (Create)
```swift
// Plan a single day's workout
[TOOL_CALL: plan_workout(
    date: "2025-09-07",  // or "today", "tomorrow"
    workout: "75-minute steady state row at Zone 2 (18-20 spm)",
    notes: "Focus on technique, keep heart rate under 145"
)]
```

#### B. `update_workout` (Update)
```swift
// Modify an existing planned workout
[TOOL_CALL: update_workout(
    date: "2025-09-07",
    workout: "60-minute steady state row (reduced from 75 due to fatigue)",
    reason: "Athlete reported heavy legs from yesterday"
)]
```

#### C. `get_workout` (Read)
```swift
// Get a specific day's workout details
[TOOL_CALL: get_workout(date: "2025-09-07")]
// Returns: planned workout, any notes, completion status
```

#### D. `delete_workout` (Delete)
```swift
// Remove a planned workout (e.g., for unexpected rest day)
[TOOL_CALL: delete_workout(
    date: "2025-09-07",
    reason: "Athlete needs extra recovery"
)]
```

#### E. `plan_next_workout` (Adaptive Planning)
```swift
// Plan the next workout based on recent performance
[TOOL_CALL: plan_next_workout(
    based_on_feedback: "Today's workout felt good, hit all targets",
    next_date: "tomorrow"  // optional, defaults to next training day
)]
```

### 1.2 Keep But Modify Existing Tools
- `plan_week_workouts`: Keep for initial program setup or bulk planning when appropriate
- Add parameter: `adaptive_mode: true` to only plan 1-2 days ahead

## 2. System Prompt Updates

### 2.1 Change Planning Philosophy
Replace current section 9.5 with:

```markdown
## 9.5 │ ADAPTIVE WORKOUT PLANNING PROTOCOL

**PRINCIPLE: Plan adaptively based on athlete feedback and performance**

### Daily Planning Approach:
1. Plan TODAY's workout when athlete asks or at start of day
2. Wait for workout completion and feedback
3. Use feedback to inform tomorrow's workout
4. Never plan more than 2-3 days ahead unless specifically requested

### Tool Usage Flow:
```
Morning:
Coach: [TOOL_CALL: get_training_status]
Coach: [TOOL_CALL: plan_workout(date: "today", workout: "...")]
"Today's workout is ready: 75-minute steady row..."

Post-workout:
Athlete: "Completed today's row, felt strong"
Coach: [TOOL_CALL: mark_workout_complete(date: "today", notes: "felt strong")]
Coach: [TOOL_CALL: plan_next_workout(based_on_feedback: "felt strong")]
"Great work! Based on your strong performance, tomorrow we'll..."
```

### Modification Protocol:
- If athlete reports issues → use update_workout immediately
- If plans change → use update_workout with reason
- If rest needed → use delete_workout with explanation
```

### 2.2 Add Adaptive Coaching Rules
```markdown
## 10 │ ADAPTIVE COACHING RULES

### 10.1 │ LISTEN FIRST, PLAN SECOND
• Always get feedback on recent workouts before planning next
• Check for soreness, fatigue, motivation levels
• Adjust intensity based on life stress and recovery

### 10.2 │ MODIFICATION TRIGGERS
Immediately modify planned workout when:
• Athlete reports excessive fatigue (→ reduce volume 20-30%)
• Poor sleep (<6 hours) (→ reduce intensity, maintain movement)
• Work/life stress high (→ switch to recovery focus)
• Feeling strong (→ option to add 10-15% volume/intensity)

### 10.3 │ PLANNING HORIZON
• Default: Plan only today's workout
• After completion: Plan tomorrow based on feedback
• Weekly overview: Use get_weekly_schedule to show what's tentatively planned
• Emphasize: "Plans are flexible and will adapt to your progress"
```

## 3. Implementation Changes

### 3.1 ToolProcessor.swift Updates
Add new tool cases:
```swift
case "plan_workout":
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let workoutParam = toolCall.parameters["workout"] as? String ?? ""
    let notesParam = toolCall.parameters["notes"] as? String
    return try await executePlanWorkout(date: dateParam, workout: workoutParam, notes: notesParam)

case "update_workout":
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let workoutParam = toolCall.parameters["workout"] as? String ?? ""
    let reasonParam = toolCall.parameters["reason"] as? String
    return try await executeUpdateWorkout(date: dateParam, workout: workoutParam, reason: reasonParam)

case "delete_workout":
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let reasonParam = toolCall.parameters["reason"] as? String
    return try await executeDeleteWorkout(date: dateParam, reason: reasonParam)

case "plan_next_workout":
    let feedbackParam = toolCall.parameters["based_on_feedback"] as? String
    let nextDateParam = toolCall.parameters["next_date"] as? String
    return try await executePlanNextWorkout(feedback: feedbackParam, nextDate: nextDateParam)
```

### 3.2 TrainingScheduleManager.swift Updates
Add methods for single-day operations:
```swift
func planWorkout(for date: Date, workout: String, notes: String?) -> Bool
func updateWorkout(for date: Date, workout: String, reason: String?) -> Bool
func deleteWorkout(for date: Date, reason: String?) -> Bool
func getWorkout(for date: Date) -> WorkoutDay?
```

### 3.3 Data Model Enhancements
Add to WorkoutDay:
```swift
var lastModified: Date?
var modificationReason: String?
var plannedIntensity: IntensityLevel?  // enum: easy, moderate, hard, maximum
var actualIntensity: IntensityLevel?   // filled post-workout
var adaptationNotes: String?           // coach's reasoning for changes
```

## 4. Benefits of This Approach

### 4.1 For Athletes
- Workouts adapt to their actual performance and recovery
- Less overwhelming than seeing a full week planned
- Can request changes easily
- Better personalization based on feedback

### 4.2 For Coach AI
- More responsive to athlete needs
- Can make intelligent adjustments
- Builds better athlete relationship through listening
- Reduces rigid adherence to pre-planned programs

### 4.3 For System
- More flexible and maintainable
- True CRUD operations for workout management
- Better audit trail of changes and reasons
- Supports both adaptive and batch planning modes

## 5. Migration Strategy

### Phase 1: Add New Tools (Backward Compatible)
- Implement new CRUD tools alongside existing ones
- Update ToolProcessor to handle both approaches
- Test with both planning styles

### Phase 2: Update System Prompt
- Modify coach behavior to prefer adaptive planning
- Keep weekly planning for program initialization
- Add feedback-driven planning logic

### Phase 3: UI Updates (Optional)
- Show modification history in calendar
- Highlight adapted workouts
- Display adaptation reasons

## 6. Example Interactions

### Adaptive Daily Planning
```
Day 1 Morning:
Athlete: "What should I do today?"
Coach: [TOOL_CALL: get_training_status]
Coach: [TOOL_CALL: plan_workout(date: "today", workout: "70-min steady row...")]
"Today's 70-minute steady row is ready. Focus on maintaining 18-20 spm..."

Day 1 Evening:
Athlete: "Done, but legs were heavy, only did 60 minutes"
Coach: [TOOL_CALL: mark_workout_complete(date: "today", workout: "60 min row", notes: "legs heavy")]
Coach: [TOOL_CALL: plan_next_workout(based_on_feedback: "legs heavy, shortened workout")]
"Good call listening to your body. Tomorrow let's do an easy 45-minute bike for recovery..."

Day 2 Morning:
Athlete: "Actually feeling better today, can I do the original planned row?"
Coach: [TOOL_CALL: update_workout(date: "today", workout: "70-min steady row", reason: "athlete feeling recovered")]
"Updated! Let's go with the 70-minute row since you're feeling good..."
```

### Handling Changes
```
Athlete: "Unexpected work trip tomorrow, need to modify"
Coach: [TOOL_CALL: get_workout(date: "tomorrow")]
Coach: [TOOL_CALL: update_workout(date: "tomorrow", workout: "Hotel: 30-min run + bodyweight circuit", reason: "travel")]
"Adapted for travel: 30-minute run plus hotel-friendly bodyweight circuit..."
```

## 7. Success Metrics
- Reduction in skipped/incomplete workouts
- Increase in athlete satisfaction feedback
- Better adherence to program over time
- More appropriate workout-to-recovery balance

## 8. Technical Implementation Priority
1. **High Priority**: Implement single-day plan_workout and update_workout tools
2. **Medium Priority**: Add plan_next_workout for adaptive planning
3. **Low Priority**: Enhanced UI features and modification history