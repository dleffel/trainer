# "Unknown" Results Root Cause Analysis

## Problem Statement

Workout results sometimes display as "• Unknown" in the Results section of the calendar view, providing no useful information about which exercise was logged.

## Root Cause

The issue originates in [`WorkoutToolExecutor.swift`](TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift:87-91), which provides a fallback value of `"Unknown"` when the LLM fails to provide the exercise name using any of the expected parameter names:

```swift
let exercise = (params["exercise"] as? String)
    ?? (params["exerciseName"] as? String)
    ?? (params["movement"] as? String)
    ?? (params["name"] as? String)
    ?? "Unknown"  // ⚠️ SILENT FAILURE - No error, no feedback to LLM
```

### Why This Happens

The LLM calls `log_set_result` but either:
1. Uses a parameter name not in the alias list (e.g., `workout_name`, `exercise_type`, etc.)
2. Makes a mistake in the tool call structure
3. Has a parsing error that prevents parameter extraction

Instead of **failing fast with a clear error message**, the code silently accepts "Unknown" as a valid exercise name, which then:
- Passes the non-empty validation in [`WorkoutSetResult.swift:58-60`](TrainerApp/TrainerApp/Models/WorkoutSetResult.swift:58-60)
- Gets persisted to storage
- Displays to the user as unhelpful "• Unknown" entries

## Current System Behavior

### Parameter Resolution Cascade
Per [`SystemPrompt.md:482`](TrainerApp/TrainerApp/SystemPrompt.md:482), the documented parameter is:
- **Primary**: `exercise` (string, required)
- **Aliases**: `exerciseName`, `movement`, `name`

### Validation Flow
1. **Tool Executor** (lines 87-91): Tries 4 parameter names → defaults to "Unknown"
2. **WorkoutSetResult Init** (lines 32-53): Accepts any non-empty string
3. **Validation** (lines 56-60): Only checks if trimmed string is empty
4. **Result**: "Unknown" passes all validation ✓ but provides no value ✗

## Impact

**User Experience:**
- Workout logs show "• Unknown" entries with weight/reps but no exercise identification
- Makes historical data review impossible for these entries
- Degrades trust in the coaching system

**LLM Behavior:**
- LLM receives `success: true` response even though it used wrong parameter names
- No feedback loop to correct its behavior
- May continue making the same mistake

**Data Quality:**
- Invalid data persists in storage
- Cannot be retroactively fixed without exercise name
- Pollutes workout history

## Proposed Solutions

### Option 1: Fail Fast (Recommended)

**Change**: Reject tool calls that don't provide a recognized exercise parameter

```swift
// In WorkoutToolExecutor.swift (lines 87-91)
guard let exercise = (params["exercise"] as? String)
    ?? (params["exerciseName"] as? String)
    ?? (params["movement"] as? String)
    ?? (params["name"] as? String) else {
    return ToolProcessor.ToolCallResult(
        toolName: toolCall.name,
        result: "[Error: Missing required 'exercise' parameter. You must provide the exercise name using one of: exercise, exerciseName, movement, or name]",
        success: false
    )
}
```

**Benefits:**
- ✅ Prevents invalid data from being persisted
- ✅ Gives LLM immediate, actionable feedback
- ✅ Creates a feedback loop for LLM to correct behavior
- ✅ Maintains data quality

**Drawbacks:**
- ⚠️ Slightly more verbose error handling
- ⚠️ May initially cause more failed tool calls until LLM adapts

### Option 2: Enhanced Validation (Complementary)

**Change**: Add "Unknown" to the validation blacklist

```swift
// In WorkoutSetResult.swift (lines 56-60)
private func validate() throws {
    let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Exercise name validation
    if trimmed.isEmpty || trimmed.lowercased() == "unknown" {
        throw WorkoutSetResultError.invalidExerciseName
    }
    // ... rest of validation
}
```

**Benefits:**
- ✅ Defense in depth - catches "Unknown" at model level
- ✅ Prevents any code path from persisting "Unknown"

### Option 3: Debug Logging (Diagnostic)

**Change**: Add logging when parameter aliases are tried

```swift
// In WorkoutToolExecutor.swift (before line 87)
print("🔍 DEBUG log_set_result parameters: \(params.keys.sorted())")

let exercise = (params["exercise"] as? String)
    ?? (params["exerciseName"] as? String)
    ?? (params["movement"] as? String)
    ?? (params["name"] as? String)
    ?? {
        print("⚠️ WARNING: No exercise parameter found in: \(params.keys)")
        return "Unknown"
    }()
```

**Benefits:**
- ✅ Helps diagnose which parameter names LLM is actually using
- ✅ Can identify if more aliases are needed
- ✅ Minimal code change

### Option 4: Parameter Name Expansion (Preventive)

**Change**: Add more common parameter name aliases

```swift
let exercise = (params["exercise"] as? String)
    ?? (params["exerciseName"] as? String)
    ?? (params["movement"] as? String)
    ?? (params["name"] as? String)
    ?? (params["workout"] as? String)        // NEW
    ?? (params["exercise_name"] as? String)  // NEW (snake_case)
    ?? (params["lift"] as? String)           // NEW (powerlifting term)
```

**Benefits:**
- ✅ More forgiving to LLM variations
- ✅ Reduces false failures

**Drawbacks:**
- ⚠️ Masks the real problem (LLM not following spec)
- ⚠️ May hide bugs in parameter extraction

## Recommended Implementation Plan

### Phase 1: Immediate Fix (Fail Fast)
1. Implement Option 1 (guard statement) in `WorkoutToolExecutor.swift`
2. Implement Option 2 (validation blacklist) in `WorkoutSetResult.swift`
3. Update error messages to be clear and actionable

### Phase 2: Diagnostics (Understanding the Problem)
1. Implement Option 3 (debug logging) temporarily
2. Monitor logs to see what parameter names LLM actually uses
3. Identify patterns in failed calls

### Phase 3: Refinement (Based on Data)
1. If logs show LLM consistently using specific unrecognized names:
   - Either add those as aliases (Option 4)
   - Or improve SystemPrompt to be more explicit about parameter names
2. If logs show random variations:
   - Focus on improving LLM prompt clarity
   - Consider adding examples in SystemPrompt

### Phase 4: Cleanup
1. Remove "Unknown" fallback entirely
2. Remove temporary debug logging (or make it conditional on debug mode)
3. Add unit tests for parameter extraction edge cases

## Testing Strategy

### Unit Tests
```swift
func testLogSetResultWithoutExerciseName() {
    // Call log_set_result with no exercise parameter
    // Expect: ToolCallResult with success=false and error message
}

func testLogSetResultWithUnknownExerciseName() {
    // Call log_set_result with exercise="Unknown"
    // Expect: Validation error
}

func testLogSetResultWithVariousAliases() {
    // Test each alias: exercise, exerciseName, movement, name
    // Expect: All succeed with correct exercise name
}
```

### Integration Tests
1. Test in actual conversation with coach
2. Intentionally trigger the error (remove exercise param)
3. Verify LLM receives error and can correct itself
4. Verify no "Unknown" entries in storage

## Success Criteria

✅ No new "• Unknown" entries appear in Results section  
✅ LLM receives clear error when it omits exercise parameter  
✅ LLM successfully retries with correct parameter  
✅ All legitimate exercise names still log correctly  
✅ Historical "Unknown" entries remain (for audit trail) but no new ones created

## Files to Modify

1. **[`TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift`](TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift)** (lines 87-91)
   - Replace `?? "Unknown"` with guard statement
   - Add error return with helpful message

2. **[`TrainerApp/TrainerApp/Models/WorkoutSetResult.swift`](TrainerApp/TrainerApp/Models/WorkoutSetResult.swift)** (lines 56-60)
   - Add "unknown" to validation blacklist
   - Improve error message

3. **[`TrainerApp/TrainerApp/SystemPrompt.md`](TrainerApp/TrainerApp/SystemPrompt.md)** (lines 475-495) (Optional)
   - Make exercise parameter requirement more prominent
   - Add warning about what happens if omitted

## Related Issues

- Data quality concerns with persisted "Unknown" values
- Lack of feedback loop when LLM uses wrong parameter names
- Silent failures in tool call parameter extraction