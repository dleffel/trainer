# Block Focus Refactoring Plan

## Problem Statement

The `generateBlockContext()` method in TrainingScheduleManager contains critical "Block Focus" information that guides workout planning. However, this information is only provided as dynamic context, making it less prominent than it should be when the LLM calls `plan_workout`.

**Current Location**: Lines 634-679 of [`TrainingScheduleManager.swift`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:634)

## Proposed Solution

Move the block-specific planning guidance from the dynamic context into the static system prompt, while keeping the current state information (which block, which week) in the dynamic context.

## Changes Required

### 1. Update SystemPrompt.md

**Location**: Section 6.5 "WORKOUT PLANNING CONSIDERATIONS" → subsection A "REVIEW BLOCK CONTEXT"

**Add new subsection with detailed block-specific guidance**:

```markdown
### A. REVIEW BLOCK CONTEXT

Ask yourself:
- What block are we in? (Hypertrophy-Strength, Aerobic-Capacity, Deload, etc.)
- What week within this block? (affects intensity and volume progression)
- What are the block-specific goals?

#### HYPERTROPHY-STRENGTH BLOCK (10 weeks)

**Primary Focus**: Build muscle mass and base strength

**Training Parameters**:
- Volume: High training volume with moderate intensity
- Sessions: 5-6 per week (2-3 strength + 3-4 aerobic)
- Rep Ranges: 6-12 reps for primary lifts
- Emphasis: Compound movements, progressive volume increases

**Week-Specific Progression**:
- **Weeks 1-3**: Establishing movement patterns and baseline loads
  - Focus on technique refinement
  - Find appropriate working weights (3-4 RIR on first sets)
  - Build volume tolerance gradually
  
- **Weeks 4-7**: Progressive overload with increasing volume
  - Increase volume by adding sets or exercises
  - Target loads: 2-3 RIR on final sets
  - Balance push/pull, upper/lower throughout week
  
- **Weeks 8-10**: Peak volume before transitioning to next block
  - Highest volume of the block
  - Maintain intensity while pushing volume limits
  - Prepare for deload recovery

#### AEROBIC-CAPACITY BLOCK (8 weeks)

**Primary Focus**: Develop aerobic capacity and endurance

**Training Parameters**:
- Volume: High aerobic volume with varied intensities
- Sessions: 6-8 per week (mostly aerobic with 1-2 strength maintenance)
- Modalities: Rowing, running, cycling (vary throughout week)
- Heart Rate Zones: Z2 (60-70% max), Threshold (80-90%), VO2max (90-100%)

**Week-Specific Progression**:
- **Weeks 1-2**: Base building with Zone 2 emphasis
  - 80% of aerobic work in Z2
  - Long steady-state sessions (60-90 min)
  - Minimal intensity work
  
- **Weeks 3-5**: Adding threshold and VO2max intervals
  - Introduce 2x threshold sessions per week
  - Add 1x VO2max session
  - Maintain Z2 base (50% of aerobic volume)
  
- **Weeks 6-8**: Peak aerobic capacity development
  - High-intensity interval focus
  - 2-3x threshold/VO2max sessions
  - Shorter Z2 sessions for recovery

#### DELOAD BLOCK (1 week)

**Primary Focus**: Recovery and adaptation

**Training Parameters**:
- Volume: Reduced to 40-50% of normal training load
- Intensity: Maintain movement quality but reduce absolute loads
- Sessions: Focus on technique, mobility, and active recovery
- Purpose: Allow body to adapt to previous training block

**Planning Guidelines**:
- Reduce sets by 50% for all strength exercises
- Cut aerobic duration by 50%
- Maintain exercise variety but lower intensity
- Add extra mobility/yoga sessions
- Prioritize sleep and recovery

#### RACE-PREP BLOCK

**Primary Focus**: Race-specific preparation

**Training Parameters**:
- Volume: High intensity with race-pace work
- Sessions: Race simulations and specific intervals
- Focus: Race-specific energy systems and pacing
- Mental: Practice race-day routines and nutrition

**Planning Guidelines**:
- Include race-pace intervals 2-3x per week
- Simulate race conditions (time of day, nutrition, warm-up)
- Progressive increase in race-intensity work
- Maintain strength with reduced volume

#### TAPER BLOCK

**Primary Focus**: Peak for race day

**Training Parameters**:
- Volume: Progressively reduced while maintaining intensity
- Sessions: Short, sharp workouts with full recovery
- Purpose: Maximize freshness while maintaining fitness
- Duration: Typically 1-2 weeks before race

**Planning Guidelines**:
- Week 1: 60-70% normal volume, maintain intensity
- Week 2: 40-50% normal volume, short high-intensity efforts
- Include race-pace work but very brief (5-10 min)
- Extra rest days, focus on sleep and recovery
```

### 2. Simplify TrainingScheduleManager.generateBlockContext()

**Current**: Lines 620-683 contain both state information AND planning guidance (including week-specific focus logic)

**Revised**: Keep ONLY pure state information - no interpretation, no guidance, just facts

```swift
func generateBlockContext() -> String {
    guard let block = currentBlock, let program = currentProgram else {
        return "## CURRENT TRAINING BLOCK\n\nNo active training program.\n"
    }
    
    var context = "## CURRENT TRAINING BLOCK\n\n"
    
    // PURE STATE ONLY - no interpretation or guidance
    context += "**Block Type**: \(block.type.rawValue)\n"
    context += "**Week in Block**: \(currentWeekInBlock) of \(block.type.duration)\n"
    context += "**Total Week in Program**: \(totalWeekInProgram) of 20\n"
    context += "**Program Started**: \(formatDate(program.startDate))\n"
    
    return context
}
```

**Rationale**: The LLM should use the system prompt guidance to determine what the week focus should be based on the block type and week number. No need to hardcode that logic.

### 3. Benefits of This Refactoring

1. **Increased Prominence**: Block-specific guidance is now in the system prompt where it has more "weight" in the LLM's decision-making
2. **Better Reference**: The LLM can refer to the comprehensive guidance in the system prompt while using the dynamic context for current state
3. **Clearer Separation**: Dynamic context focuses on "what" (current state) while system prompt focuses on "how" (planning guidance)
4. **Easier Maintenance**: All planning guidance is centralized in one location (system prompt)
5. **Reduced Duplication**: No need to repeat the same guidance in dynamic context every time

## Implementation Steps

1. [ ] Update [`SystemPrompt.md`](TrainerApp/TrainerApp/SystemPrompt.md) Section 6.5.A with detailed block-specific guidance
2. [ ] Refactor [`TrainingScheduleManager.generateBlockContext()`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:620) to focus on state only
3. [ ] Test that the system prompt loads correctly
4. [ ] Verify that workout planning still works as expected with the new structure

## Testing Considerations

After implementation:
- Test workout planning in each block type
- Verify that the LLM considers block-specific guidance when planning
- Check that the dynamic context still provides current week information
- Ensure no regression in workout quality or adherence to block principles