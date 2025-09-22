# Enhanced Schedule Snapshot Plan

## Problem Statement

Currently, the system prompt enhancement only shows minimal information like "Workout scheduled" when much richer workout and progression data is available. The coach needs detailed context about:
- What specific workout is planned for today
- How today's workout fits into the current training block progression  
- Detailed workout parameters (duration, focus, intensity zones)
- Comparison with expected templates vs. actual planned workouts
- Recent workout completion status and progression indicators

## Current Implementation Analysis

### Current Schedule Snapshot Structure
Located in [`TrainingScheduleManager.generateScheduleSnapshot()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:854):

```swift
// Current minimal output:
"- **Tuesday**: Workout scheduled"
"- **Wednesday (TODAY)**: Workout planned ⚡"
```

### Available Rich Data Sources

1. **WorkoutTemplate** - Structured templates with:
   - `title`, `summary`, `focus`, `durationMinutes`
   - `sessionType`, `modalityPrimary`, `intensityZone`
   - `icon`, `notes`

2. **StructuredWorkout** - Actual planned workouts with:
   - Exercise details, sets, reps, weights
   - `displaySummary`, `totalDuration`
   - Exercise distribution (cardio/strength/mobility)

3. **TrainingBlock Context**:
   - Current block type (hypertrophyStrength, aerobicCapacity, deload)
   - Week within block vs. total program week
   - Block-specific training focuses and goals

## Enhanced Schedule Snapshot Design

### New Information Structure

```markdown
## CURRENT SCHEDULE SNAPSHOT
**Generated**: Oct 16, 2025 at 4:15 PM
**Program**: Week 1 of 20 - Hypertrophy-Strength Block (Week 1 of 10)

### TODAY'S FOCUS
**Thursday**: Strength - Upper + Z2
- **Template**: Upper body strength (press/pull) → 30-40' Z2 spin
- **Planned**: [ACTUAL WORKOUT DETAILS IF AVAILABLE]
- **Duration**: 90 minutes
- **Focus**: Hypertrophy (upper body); easy aerobic
- **Intensity**: Strength + Z2
- **Status**: Workout planned ⚡

### THIS WEEK PROGRESSION
- **Monday**: Rest Day - Mobility + core (20') ✅ Completed
- **Tuesday**: Lower + Z2 - Squat/hinge → erg Z2 (90') ✅ Completed  
- **Wednesday**: RowErg Z2 + Technique (60') ✅ Completed
- **Thursday (TODAY)**: Upper + Z2 - Press/pull → bike Z2 (90') ⚡ PLANNED
- **Friday**: Planned - Long Workout (TBD)
- **Saturday**: Planned - Long Workout (TBD) 
- **Sunday**: Planned - Long Workout (TBD)

### BLOCK PROGRESSION CONTEXT
**Hypertrophy-Strength Block Goals**:
- Primary: Build muscle mass and base strength
- Volume: High training volume with moderate intensity
- Expected: 5-6 sessions/week, 2-3 strength + 3-4 aerobic
- Week 1 Focus: Establishing movement patterns and baseline loads

### RECENT PERFORMANCE INDICATORS
- **Load Progression**: [If available from recent workouts]
- **Volume Completion**: 3/7 sessions completed this week
- **Block Adherence**: On track with template expectations
```

## Implementation Plan

### Phase 1: Enhanced Data Collection Methods

#### 1.1 Extend TrainingScheduleManager Methods
- Add `getDetailedWorkoutInfo(for date: Date)` method
- Add `getBlockProgressionContext()` method  
- Add `getWeeklyCompletionStatus()` method

#### 1.2 WorkoutDay Enhancement  
- Add computed property for template vs. actual workout comparison
- Add workout completion tracking
- Add recent performance indicators

### Phase 2: Enhanced Snapshot Generation

#### 2.1 Modify `generateScheduleSnapshot()` 
Replace current minimal output with rich structured information:

```swift
func generateScheduleSnapshot() -> String {
    // ... existing program initialization logic ...
    
    var snapshot = generateBasicHeader()
    snapshot += generateTodaysFocus()
    snapshot += generateWeeklyProgression()
    snapshot += generateBlockContext()
    snapshot += generatePerformanceIndicators()
    
    return snapshot
}
```

#### 2.2 New Helper Methods
- `generateTodaysFocus()` - Detailed today's workout info
- `generateWeeklyProgression()` - Week overview with completion status
- `generateBlockContext()` - Training block goals and progression
- `generatePerformanceIndicators()` - Recent performance data

### Phase 3: Template vs. Actual Workout Comparison

#### 3.1 Workout Variance Detection
- Compare planned workout against expected template
- Highlight deviations or customizations
- Show progression adaptations

#### 3.2 Smart Status Indicators
- ✅ Completed with expected parameters
- ⚠️ Completed with modifications  
- ⚡ Planned for today
- 📋 Template available, needs planning
- ❌ Missing/skipped

### Phase 4: Performance Integration

#### 4.1 Recent Workout Data
- Load progression indicators
- Volume completion rates
- RPE/RIR trends (if available)

#### 4.2 Block Adherence Metrics
- Sessions completed vs. expected
- Training load distribution
- Recovery indicators

## Technical Implementation Details

### Core Changes Required

1. **TrainingScheduleManager.swift** - Enhanced snapshot generation
2. **WorkoutDay.swift** - Additional computed properties for rich data
3. **SystemPromptLoader.swift** - No changes needed (uses existing snapshot method)

### Data Flow
```
SystemPromptLoader.loadSystemPromptWithSchedule()
    ↓
TrainingScheduleManager.generateScheduleSnapshot()
    ↓
Enhanced rich snapshot with:
    - Today's detailed workout info
    - Weekly progression context  
    - Block-specific goals
    - Performance indicators
```

### Backward Compatibility
- Maintain existing `generateScheduleSnapshot()` signature
- Graceful degradation if workout data unavailable
- Fallback to current minimal format if errors occur

## Expected Benefits

1. **Improved Coach Context**: Coach AI gets detailed workout information instead of just "Workout scheduled"

2. **Better Decision Making**: Rich progression context enables smarter workout adaptations

3. **Enhanced User Experience**: More informed coaching based on actual training plan details

4. **Training Adherence**: Clear visibility into weekly progression and block goals

## Implementation Priority

**High Priority**:
- Today's detailed workout information
- Weekly progression overview
- Block context integration

**Medium Priority**:  
- Performance indicators
- Template vs. actual comparison
- Advanced status indicators

**Low Priority**:
- Historical trend analysis
- Predictive progression modeling

## Next Steps

1. Review this plan for completeness and accuracy
2. Confirm enhanced snapshot format meets requirements  
3. Proceed to implementation in Code mode
4. Test enhanced system prompt generation
5. Validate coach AI receives proper context

---

This plan transforms the minimal "Workout scheduled" into a rich, contextual snapshot that provides the coach AI with comprehensive information about the athlete's training plan, progression, and current status.