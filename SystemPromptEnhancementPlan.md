# System Prompt Enhancement Plan: Thoughtful Workout Planning

## Problem Statement

The coach currently has access to rich contextual data when planning workouts via `plan_workout`, but the system prompt doesn't explicitly guide the coach to USE this context. Available context includes:

1. **Block Context** (via `generateBlockContext()`)
   - Current block type (Hypertrophy-Strength, Aerobic-Capacity, Deload, etc.)
   - Week within block (e.g., "Week 3 of 10")
   - Total week in 20-week program
   - Block-specific focus and goals

2. **Schedule Snapshot** (via `generateScheduleSnapshot()`)
   - Last 30 days of workouts with full exercise details
   - Actual results logged (sets, reps, weight, RIR, RPE)
   - Pattern analysis opportunities

3. **Current Context**
   - Day of week (determines workout duration per template)
   - Temporal information (conversation timing)

**The Issue:** The coach may plan workouts without carefully considering:
- What block-specific adaptations should be targeted
- Which exercises were done recently (avoiding premature repetition)
- What loads/intensities were used previously (for progression)
- Whether the week's workouts are properly balanced
- Whether the workout duration matches the day-of-week template

## Proposed Solution

Add a new section to [`SystemPrompt.md`](TrainerApp/TrainerApp/SystemPrompt.md) that provides explicit guidance on workout planning considerations.

### Section Structure

Insert a new **Section 6.5: WORKOUT PLANNING CONSIDERATIONS** between the current tool descriptions and the Micro-Check section. This section will:

1. **Mandate Context Review**
   - MUST review block context before planning
   - MUST check last 30 days to avoid premature exercise repetition
   - MUST consult past results for progressive overload

2. **Block-Specific Guidance**
   - Different planning approaches for Hypertrophy-Strength vs Aerobic-Capacity
   - Week-specific progression strategies within each block
   - Deload week modifications

3. **Weekly Structure Compliance**
   - Monday: Full rest (with mobility/yoga entry)
   - Tuesday/Thursday/Friday: Long workouts (60-90 min)
   - Wednesday: Short workout (30-45 min)
   - Saturday/Sunday: Long workouts, may be 1-2 sessions

4. **Exercise Selection Strategy**
   - Minimum 7-10 days between same strength exercises (exceptions for program staples)
   - Vary cardio modalities throughout the week
   - Balance push/pull, upper/lower within the week
   - Consider accumulated fatigue when sequencing

5. **Progressive Overload Decision Tree**
   - Review last performance of same exercise
   - If all sets hit target reps with ≤1 RIR → increase load
   - If new exercise variant → use discovery protocol (3-4 RIR first set)
   - Maintain clear progression trajectory across weeks

6. **Workout Composition Guidelines**
   - Title should reflect primary focus
   - Select appropriate icon for workout type
   - Balance exercise types (strength + mobility, cardio + strength, etc.)
   - Notes should include coaching cues or context

## Detailed Section Content

```markdown
### 6.5 WORKOUT PLANNING CONSIDERATIONS

**Before calling `plan_workout`, you MUST thoughtfully consider the following:**

#### A. REVIEW BLOCK CONTEXT

Ask yourself:
- What block are we in? (Hypertrophy-Strength, Aerobic-Capacity, Deload, etc.)
- What week within this block? (affects intensity and volume progression)
- What are the block-specific goals? (see Section 2.1 for block focuses)

**Example Block-Specific Adaptations:**
- **Hypertrophy-Strength Block**: Emphasize compound lifts, 6-12 rep ranges, progressive volume increases
- **Aerobic-Capacity Block**: Prioritize rowing/running/biking, varied interval structures, Zone 2 base building
- **Deload Week**: Reduce volume 30-40%, maintain movement quality, add extra mobility

#### B. CHECK RECENT WORKOUT HISTORY

Before selecting exercises, review the last 30 days:
- **Avoid premature repetition**: Main strength exercises should have 7-10 days between sessions (except program staples like squats, deadlifts, rows)
- **Vary cardio modalities**: Don't repeat the same cardio workout structure within 5-7 days
- **Balance the week**: Ensure the current week includes appropriate variety of push/pull, upper/lower, cardio types

**Tool**: Use the schedule snapshot data (automatically provided in context) to check what's been done recently.

#### C. USE PAST RESULTS FOR PROGRESSION

When planning strength exercises:
1. **Find last performance**: Look for the most recent time this exercise (or similar variant) was performed
2. **Evaluate RIR/RPE**: 
   - If all sets achieved ≤1 RIR → increase load (upper body +5lb, lower body +10lb)
   - If RIR was 3-4 on any set → keep same load
   - If RIR was 0 or sets failed → reduce load 5-10lb
3. **New exercise**: Start with discovery protocol (3-4 RIR first set, adjust within workout)

**Tool**: Review logged results from schedule snapshot to inform load selection.

#### D. HONOR DAY-OF-WEEK TEMPLATE

Match workout duration to the day (Section 2.2):
- **Monday**: Full rest (plan mobility/yoga/recovery with appropriate icon)
- **Tuesday, Thursday, Friday**: Long workouts (60-90 minutes)
- **Wednesday**: Short workout (30-45 minutes)
- **Saturday, Sunday**: Long workouts (may split into 2 sessions)

#### E. THOUGHTFUL EXERCISE SELECTION

Consider:
- **Block alignment**: Does this exercise support the current block's goals?
- **Recovery state**: Is the athlete recovered enough for high-intensity work?
- **Weekly balance**: Does this workout complement others in the week?
- **Movement quality**: Are we maintaining technical standards?
- **Equipment available**: Only use equipment from Section 2.3

#### F. STRUCTURED WORKOUT COMPOSITION

When creating the `workout_json`:
1. **Title**: Should clearly reflect the primary focus (e.g., "Upper Body Strength", "Threshold Intervals")
2. **Icon**: Select appropriate SF Symbol from the icon list (Section 7.2)
3. **Exercise order**: 
   - Strength: Compound lifts first, accessories after
   - Cardio: Warm-up, main work, cool-down structure
   - Mixed: Strength before cardio when both present
4. **Notes**: Include relevant coaching cues, modifications, or context

**CRITICAL**: Every `plan_workout` call should reflect thoughtful analysis of block goals, recent training, progressive overload principles, and weekly structure. Do NOT simply create generic workouts without considering these factors.
```

## Implementation Steps

1. **Edit SystemPrompt.md**
   - Insert new Section 6.5 after current Section 6 (Adaptive Planning Protocol)
   - Renumber subsequent sections (current Section 7 becomes 7, etc.)

2. **Update Section Cross-References**
   - Update any references to section numbers in later sections
   - Ensure "Micro-Check" section references are updated

3. **Test Prompt Changes**
   - Deploy updated system prompt
   - Test with coach conversations to verify:
     - Coach reviews block context before planning
     - Coach checks recent workouts to avoid repetition
     - Coach uses past results for load progression
     - Workouts match day-of-week duration expectations

## Expected Outcomes

After implementing this enhancement:

1. **More Intelligent Planning**: Coach will actively use available context rather than planning in isolation
2. **Better Progression**: Workouts will show clear progression based on past results
3. **Improved Variety**: Less repetition of exercises, better weekly balance
4. **Block-Aligned Workouts**: Each workout will appropriately target the current training block's goals
5. **Appropriate Duration**: Workouts will match expected duration for day of week

## Risks and Mitigation

**Risk**: Prompt becomes too long, affecting token usage
- **Mitigation**: This section is prescriptive but not excessively long (~500 words). It replaces vague guidance with specific rules.

**Risk**: Coach might over-analyze and take longer to respond
- **Mitigation**: The guidance is structured as a checklist, making it easy to follow systematically

**Risk**: Coach might rigidly follow rules without adapting
- **Mitigation**: Section 6 (Adaptive Planning) still allows flexibility based on athlete feedback

## Success Metrics

- Coach references block context in explanations (observable in conversation)
- Strength exercises show appropriate load progression based on past results
- Minimum 7-10 day spacing between main lifts (can verify from schedule)
- Weekly workout distribution matches template (Mon rest, proper long/short days)
- Exercise variety improves (fewer back-to-back repeats)