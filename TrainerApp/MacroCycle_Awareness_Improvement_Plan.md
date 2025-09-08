# Macro Cycle Awareness Improvement Plan

## Problem Analysis

The coach currently receives training status information including:
- Current block type (Hypertrophy-Strength, Aerobic-Capacity, Deload)
- Week number within block
- Overall progress in 20-week cycle

However, when planning workouts via `plan_workout`, the coach:
1. Simply passes a workout description string
2. Has no validation that workouts match the current phase
3. Lacks specific templates or guidelines for each training block
4. May not be considering the block type when generating workouts

## Root Causes

1. **No Phase-Specific Workout Logic**: The `plan_workout` tool accepts any workout text without validation
2. **Insufficient System Prompt Guidance**: The prompt mentions blocks but lacks specific workout examples for each phase
3. **Missing Context Reinforcement**: The coach doesn't automatically check training status before planning workouts
4. **No Workout Templates**: No built-in templates for different block types

## Proposed Solutions

### Solution 1: Enhanced System Prompt with Phase-Specific Guidelines

**Approach**: Strengthen the SystemPrompt.md with detailed workout templates for each block type

**Implementation**:
1. Add specific workout examples for Hypertrophy-Strength block:
   - Heavy lifting days (3-5 reps)
   - Volume days (8-12 reps)
   - Specific exercises and progressions

2. Add specific workout examples for Aerobic-Capacity block:
   - Zone 2 steady state rows
   - Tempo runs/bikes
   - Duration and intensity guidelines

3. Add deload week specifics:
   - 30% volume reduction examples
   - Active recovery options
   - Mobility focus sessions

4. Include mandatory workflow:
   - ALWAYS check `get_training_status` before planning
   - Reference block type in workout description
   - Include phase-appropriate intensities

### Solution 2: Add Workout Validation/Suggestion Tool

**Approach**: Create a new tool that suggests appropriate workouts based on current phase

**Implementation**:
1. New tool: `suggest_phase_workout`
   - Input: date, athlete feedback
   - Output: phase-appropriate workout suggestion
   
2. Workout validation in `plan_workout`:
   - Check if workout matches current block type
   - Warn if intensity seems inappropriate
   - Suggest modifications if needed

### Solution 3: Context-Aware Workout Generation

**Approach**: Modify the workout planning flow to always include phase context

**Implementation**:
1. Update `plan_workout` to internally check current block
2. Prepend block context to saved workouts
3. Add phase indicator to workout descriptions
4. Include week-specific progressions

### Solution 4: Phase-Specific Workout Library

**Approach**: Create a structured workout library organized by block type

**Implementation**:
1. Create `WorkoutLibrary.swift` with templates:
   ```swift
   struct WorkoutTemplate {
       let blockType: BlockType
       let weekRange: Range<Int>
       let dayType: DayOfWeek
       let workoutOptions: [String]
   }
   ```

2. Populate with phase-appropriate workouts
3. Reference in tool responses
4. Allow coach to select and customize

## Recommended Implementation Order

### Phase 1: Quick Fix (Immediate)
Update SystemPrompt.md with:
- Explicit instruction to ALWAYS check training status first
- Phase-specific workout examples
- Clear guidelines for each block type
- Reminder to mention current block in workout descriptions

### Phase 2: Enhanced Tools (Short-term)
1. Add workout suggestion helper
2. Include phase validation in plan_workout
3. Provide feedback when workouts don't match phase

### Phase 3: Full Integration (Long-term)
1. Build comprehensive workout library
2. Implement smart workout generation
3. Add progression tracking
4. Include automatic phase-based adjustments

## Specific Changes Needed

### 1. SystemPrompt.md Updates
```markdown
### WORKOUT PLANNING BY PHASE

#### Hypertrophy-Strength Block (Weeks 1-10)
FOCUS: Building muscle and strength
- Tuesday: Lower body strength (Squats, Deadlifts)
- Thursday: Upper body strength (Bench, Rows)
- Friday: Full body volume
- Weekend: Mixed strength + conditioning

Example Tuesday:
"Lower Strength Day:
- Squat: 3×5 @ 85% (rest 3-4 min)
- RDL: 3×8 @ 70%
- Leg Press: 3×12
- Core circuit: 3 rounds"

#### Aerobic-Capacity Block (Weeks 12-19)
FOCUS: Building endurance base
- Tuesday: Long steady row (60-75 min @ Zone 2)
- Thursday: Tempo intervals
- Friday: Mixed cardio
- Weekend: Long endurance sessions

Example Tuesday:
"Aerobic Base Building:
- 70-min steady row @ Zone 2 (135-145 HR)
- Rate: 18-20 spm
- Focus on consistent pace
- 10-min mobility cool-down"

#### Deload Weeks (Weeks 11, 20)
FOCUS: Recovery and adaptation
- Reduce volume by 30%
- Maintain intensity but fewer sets
- Add mobility and recovery work
```

### 2. Tool Enhancement
Add to ToolProcessor.swift:
```swift
private func validateWorkoutForPhase(workout: String, blockType: BlockType) -> Bool {
    // Check if workout matches expected patterns for block type
}

private func suggestPhaseWorkout(for date: Date) -> String {
    // Generate phase-appropriate workout suggestion
}
```

### 3. Workflow Update
Modify the coach's interaction pattern:
1. User asks for workout
2. Coach: `[TOOL_CALL: get_training_status]`
3. Coach analyzes current block
4. Coach: `[TOOL_CALL: plan_workout]` with phase-appropriate content
5. Coach mentions the block type in response

## Success Metrics

1. **Workouts match training phase** - Strength work in strength blocks, endurance in aerobic blocks
2. **Coach mentions current block** - Every workout includes phase context
3. **Appropriate intensities** - Heavy during strength, Zone 2 during aerobic
4. **Proper deload implementation** - 30% volume reduction during deload weeks
5. **Progressive overload** - Workouts progress appropriately within each block

## Testing Plan

1. Test workout generation in different phases
2. Verify phase-appropriate exercise selection
3. Check intensity prescriptions match block type
4. Validate deload week volume reductions
5. Confirm progression through weeks within blocks

## Timeline

- **Immediate** (Today): Update SystemPrompt.md with detailed phase guidelines
- **Week 1**: Implement workout validation
- **Week 2**: Add suggestion tools
- **Week 3**: Build workout library
- **Week 4**: Full integration testing