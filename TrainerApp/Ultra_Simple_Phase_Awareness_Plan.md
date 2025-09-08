# Ultra-Simple Phase Awareness Plan

## The Simplest Possible Fix

### Single Code Change

In `ToolProcessor.swift`, modify the `executeGetTrainingStatus` response to add one line:

```swift
private func executeGetTrainingStatus() async throws -> String {
    // ... existing code to get block, week, etc ...
    
    return """
    [Training Status]
    • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
    • Overall Progress: Week \(totalWeek) of 20
    • Today: \(day.name)
    
    Plan a workout appropriate for \(block.type.rawValue) Week \(week).
    """
}
```

That's it for code changes. One line added.

### System Prompt Addition

Add this single section to `SystemPrompt.md`:

```markdown
## PHASE-AWARE WORKOUT PLANNING

**Critical Rule**: ALWAYS check [TOOL_CALL: get_training_status] before planning any workout.
The system will tell you which training block and week you're in.
Plan workouts that are appropriate for that specific phase and week of training.

Your training blocks are:
- Hypertrophy-Strength (Weeks 1-10): Focus on building strength
- Deload (Week 11): Recovery week, reduce volume by 30%
- Aerobic-Capacity (Weeks 12-19): Focus on endurance
- Deload (Week 20): Final recovery week

The specific workout you plan should match the current block's training goals.
```

## Why This Works

1. **The AI already knows** what Hypertrophy-Strength means vs Aerobic-Capacity
2. **Simple reminder** ensures the coach pays attention to the phase
3. **No prescriptive rules** - the coach can be creative within the phase
4. **Minimal code change** - literally one line
5. **Clear instruction** in the prompt to check status first

## Implementation Time

- Code change: 2 minutes
- System prompt update: 3 minutes
- Testing: 5 minutes

Total: 10 minutes

## The Result

When the coach checks training status, they'll see:
```
[Training Status]
• Current Block: Hypertrophy-Strength (Week 7 of 10)
• Overall Progress: Week 7 of 20
• Today: Tuesday

Plan a workout appropriate for Hypertrophy-Strength Week 7.
```

That simple reminder at the end ensures they consider the phase when planning the workout.

The AI is intelligent enough to understand that:
- Hypertrophy-Strength Week 7 = heavy strength work
- Aerobic-Capacity Week 3 = endurance training
- Deload Week = reduced volume

No hand-holding needed.