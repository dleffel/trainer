# Auto Program Initialization Plan

## Current Problem
The coach currently needs to call `[TOOL_CALL: start_training_program]` when no active program exists, which:
- Adds another tool call to the chain
- Creates latency in first-time user interactions
- Requires the LLM to detect "no program" state and respond with tool calls

## Proposed Solution
Automatically initialize training programs during system prompt enhancement in `SystemPromptLoader.loadSystemPromptWithSchedule()`.

## Implementation Strategy

### 1. Modify TrainingScheduleManager.generateScheduleSnapshot()
**Current Behavior:**
```swift
func generateScheduleSnapshot() -> String {
    guard let program = currentProgram else {
        return "**Status**: No active training program"
    }
    // ... generate snapshot
}
```

**New Behavior:**
```swift
func generateScheduleSnapshot() -> String {
    // Auto-initialize program if none exists
    if currentProgram == nil {
        print("🔄 Auto-initializing training program during snapshot generation")
        startNewProgram()
    }
    
    guard let program = currentProgram else {
        return "**Status**: Error initializing program"
    }
    // ... generate snapshot with guaranteed program
}
```

### 2. Update SystemPrompt.md Workflow
**Remove all references to start_training_program tool calls:**
- Section 9.1: Remove "NO → [TOOL_CALL: start_training_program]" logic
- Section 9.2: Remove start_training_program fallback cases
- Section 14.7: Mark start_training_program as deprecated/internal

**Update workflow to:**
```
Program Status Check:
├─ Program exists in snapshot → Continue with coaching
└─ Program auto-initialized → Fresh 20-week cycle ready
```

### 3. Simplify Tool Processor
**Keep start_training_program tool for edge cases but:**
- Mark as internal/debugging tool only
- Coach should never need to call it in normal operation
- Useful for manual resets or testing

## Technical Benefits

### Tool Call Reduction
**Before:**
```
New User Experience:
User: "What's my workout today?"
Coach: [TOOL_CALL: start_training_program]
       [TOOL_CALL: plan_workout]
Total: 2 tool calls
```

**After:**
```
New User Experience:
User: "What's my workout today?"
Coach: "I've set up your 20-week training program! Today you have: [workout details]"
Total: 0 tool calls (program auto-initialized during system prompt)
```

### Performance Impact
- **Eliminates 1-2 tool calls** for new users
- **Reduces first interaction latency** by ~2-3 seconds
- **Simplifies coach logic** - no "program detection" needed

## Implementation Steps

1. **Enhance generateScheduleSnapshot()** in TrainingScheduleManager
   - Add auto-initialization logic
   - Ensure thread safety (main queue dispatch)
   - Add logging for debugging

2. **Update SystemPrompt.md**
   - Remove start_training_program from normal workflows
   - Update Section 9.1 optimized workflow
   - Simplify fallback logic in Section 9.2

3. **Test Integration**
   - Verify auto-initialization works on first launch
   - Ensure existing programs are not affected
   - Test edge cases (corrupted data, date simulation)

## Edge Cases & Considerations

### Date Simulation Support
```swift
func generateScheduleSnapshot() -> String {
    if currentProgram == nil {
        // Use DateProvider.current for simulation compatibility
        startNewProgram(startDate: DateProvider.current)
    }
    // ...
}
```

### Thread Safety
```swift
func generateScheduleSnapshot() -> String {
    // Ensure UI updates happen on main queue
    DispatchQueue.main.async {
        if currentProgram == nil {
            startNewProgram()
        }
    }
    // ...
}
```

### Error Handling
```swift
func generateScheduleSnapshot() -> String {
    if currentProgram == nil {
        do {
            startNewProgram()
        } catch {
            return "**Status**: Error initializing program: \(error.localizedDescription)"
        }
    }
    // ...
}
```

## Success Metrics

- ✅ New users get immediate workout plans (0 tool calls)
- ✅ System prompt always contains valid program data
- ✅ Coach never needs to call start_training_program in normal operation
- ✅ Maintains compatibility with existing users

## Migration Strategy

### Phase 1: Auto-Initialization
- Implement auto-init in generateScheduleSnapshot()
- Keep start_training_program tool functional
- Test with new and existing users

### Phase 2: Workflow Simplification
- Update SystemPrompt.md to remove tool call requirements
- Simplify coach decision logic
- Mark start_training_program as internal-only

### Phase 3: Validation
- Monitor tool call patterns
- Verify 0-tool-call new user experience
- Performance testing with auto-initialization

## Files to Modify

1. **TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift**
   - Enhance `generateScheduleSnapshot()` method
   - Add auto-initialization logic

2. **TrainerApp/TrainerApp/SystemPrompt.md**
   - Update Section 9.1 (OPTIMIZED SESSION WORKFLOW)
   - Simplify Section 9.2 (FALLBACK LOGIC)
   - Mark Section 14.7 (start_training_program) as internal

3. **TrainerApp/TrainerApp/Services/ToolProcessor.swift** (optional)
   - Add deprecation warnings for start_training_program
   - Keep functionality for edge cases

## Expected Outcome

**New User First Interaction:**
```
User: "Hi, I'm new to rowing. What should I do today?"

System: [Auto-initializes 20-week program during prompt enhancement]

Coach: "Welcome to your personalized 20-week rowing program! I've set you up with a progressive training plan. Today is Week 1, Day 1 of your Hypertrophy-Strength block.

Your workout today:
- 10-min warmup at easy pace
- 4 x 6min @ Zone 2 with 2min rest
- 5-min cool down

This builds your aerobic base while introducing structured training. Ready to get started?"

Total tool calls: 0
Response time: Immediate
```

This creates a seamless onboarding experience where new users immediately get actionable workout plans without any tool call overhead.