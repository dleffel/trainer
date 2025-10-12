# Strict Schema Enforcement for log_set_result

## Philosophy: Opinionated Schema Design

Instead of accepting multiple parameter name variations, we'll enforce a **single canonical schema** that the coach MUST follow. This approach:

✅ Eliminates ambiguity - one correct way to call the tool  
✅ Makes debugging easier - predictable parameter names  
✅ Prevents LLM from learning bad habits through permissive aliases  
✅ Creates clear, actionable error messages  
✅ Simplifies code maintenance  

## Canonical Schema Definition

### Required Parameters
- `exercise` (string) - Exercise name (e.g., "Bench Press", "Squat")

### Optional Parameters  
- `date` (string, default "today") - Target date for logging
- `set` (string) - Set number (e.g., "1", "2", "3")
- `reps` (string) - Number of repetitions (e.g., "8", "10")
- `load_lb` (string) - Weight in pounds (e.g., "135", "185")
- `load_kg` (string) - Weight in kilograms (e.g., "60", "100")
- `rir` (string) - Reps in Reserve, 0-10 scale (e.g., "2", "3")
- `rpe` (string) - Rate of Perceived Exertion, 1-10 scale (e.g., "7", "8")
- `notes` (string) - Additional notes about the set

### Naming Rationale

**Why `exercise` (not `exerciseName`, `movement`, `name`)?**
- Shorter and more intuitive
- Matches the domain language (workout "exercise")
- Already the primary parameter in SystemPrompt
- Unambiguous - "name" is too generic, "exerciseName" is redundant, "movement" is jargon

**Why `load_lb`/`load_kg` (not `weight_lb`, `weight_kg`)?**
- "Load" is the proper strength training term
- Distinguishes from bodyweight
- More precise language

**Why snake_case for compounds (not camelCase)?**
- Consistent with existing `load_lb`, `load_kg` in codebase
- Easier to read in tool call syntax
- Common in API design for parameter names

## Implementation Plan

### Step 1: Remove All Aliases from Code

**File:** [`WorkoutToolExecutor.swift`](TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift)

**Current (lines 87-116):**
```swift
// Be tolerant to different field names coming from the coach
let exercise = (params["exercise"] as? String)
    ?? (params["exerciseName"] as? String)
    ?? (params["movement"] as? String)
    ?? (params["name"] as? String)
    ?? "Unknown"

let setStr = (params["set"] as? String)
    ?? (params["set_number"] as? String)
    ?? (params["setIndex"] as? String)

let repsStr = (params["reps"] as? String)
    ?? (params["rep"] as? String)
    ?? (params["repetitions"] as? String)

let loadLb = (params["load_lb"] as? String)
    ?? (params["weight_lb"] as? String)

let loadKg = (params["load_kg"] as? String)
    ?? (params["weight_kg"] as? String)
```

**New (strict schema):**
```swift
// Enforce canonical schema - no aliases
guard let exercise = params["exercise"] as? String else {
    return ToolProcessor.ToolCallResult(
        toolName: toolCall.name,
        result: """
        [Error: Missing required parameter 'exercise']
        
        The log_set_result tool requires the 'exercise' parameter.
        
        Correct usage:
        log_set_result(
          exercise: "Bench Press",
          set: "1",
          reps: "8",
          load_lb: "135",
          rir: "2"
        )
        """,
        success: false
    )
}

// Extract optional parameters - strict names only
let setStr = params["set"] as? String
let repsStr = params["reps"] as? String
let loadLb = params["load_lb"] as? String
let loadKg = params["load_kg"] as? String
let rirStr = params["rir"] as? String
let rpeStr = params["rpe"] as? String
let notes = params["notes"] as? String
```

### Step 2: Add Helpful Error for Wrong Parameter Names

Add detection for common mistakes:

```swift
// Detect common parameter name mistakes and provide helpful guidance
if exercise == nil {
    var hint = ""
    if params["exerciseName"] != nil {
        hint = "\n\n❌ You used 'exerciseName' but the correct parameter is 'exercise'"
    } else if params["movement"] != nil {
        hint = "\n\n❌ You used 'movement' but the correct parameter is 'exercise'"
    } else if params["name"] != nil {
        hint = "\n\n❌ You used 'name' but the correct parameter is 'exercise'"
    } else {
        hint = "\n\n💡 Make sure you're using exactly 'exercise' as the parameter name"
    }
    
    return ToolProcessor.ToolCallResult(
        toolName: toolCall.name,
        result: "[Error: Missing required parameter 'exercise']\(hint)",
        success: false
    )
}
```

### Step 3: Update Model to Reject Aliases

**File:** [`WorkoutSetResult.swift`](TrainerApp/TrainerApp/Models/WorkoutSetResult.swift)

**Current (lines 16-30):** Has alias support in CodingKeys
```swift
enum CodingKeys: String, CodingKey {
    case timestamp
    case exerciseName
    // ...
    case exercise        // alias for exerciseName
    case set             // alias for setNumber
}
```

**New (strict schema):**
```swift
enum CodingKeys: String, CodingKey {
    case timestamp
    case exerciseName
    case setNumber
    case reps
    case loadLb
    case loadKg
    case rir
    case rpe
    case notes
    // NO ALIASES - enforce canonical names during decoding
}
```

**Update decoder (lines 83-110):**
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    
    // Require exact key - no aliases
    self.exerciseName = try container.decode(String.self, forKey: .exerciseName)
    
    // Optional fields - exact keys only
    self.setNumber = try? container.decode(Int.self, forKey: .setNumber)
    self.reps = try? container.decode(Int.self, forKey: .reps)
    self.loadLb = try? container.decode(String.self, forKey: .loadLb)
    self.loadKg = try? container.decode(String.self, forKey: .loadKg)
    self.rir = try? container.decode(Int.self, forKey: .rir)
    self.rpe = try? container.decode(Int.self, forKey: .rpe)
    self.notes = try? container.decode(String.self, forKey: .notes)
    
    // Validate
    try self.validate()
}
```

### Step 4: Enhanced Validation

Add "Unknown" and generic terms to validation blacklist:

```swift
private func validate() throws {
    let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    
    // Blacklist of invalid exercise names
    let invalidNames = ["unknown", "exercise", "workout", "movement", "n/a", ""]
    
    if trimmed.isEmpty || invalidNames.contains(lower) {
        throw WorkoutSetResultError.invalidExerciseName
    }
    
    // Must be at least 2 characters (reject single-letter entries)
    if trimmed.count < 2 {
        throw WorkoutSetResultError.invalidExerciseName
    }
    
    // ... rest of validation
}
```

Update error message:
```swift
case .invalidExerciseName:
    return "Exercise name must be specific (e.g., 'Bench Press', 'Squat'). Generic terms like 'exercise' or 'unknown' are not allowed."
```

### Step 5: Update SystemPrompt with Strict Schema

**File:** [`SystemPrompt.md`](TrainerApp/TrainerApp/SystemPrompt.md) (lines 475-511)

**Current:** Shows aliases as acceptable

**New:** Emphasize ONE correct way

```markdown
### 7.5 `log_set_result`

**Purpose:** Log a single set result with comprehensive tracking data

**IMPORTANT:** This tool has a strict parameter schema. Use the EXACT parameter names shown below.

**Required Parameters:**
* `exercise` (string) - Specific exercise name
  * ✅ Good: "Bench Press", "Back Squat", "Deadlift"
  * ❌ Bad: "Unknown", "Exercise", "workout"

**Optional Parameters:**
* `date` (string, default `"today"`) - Target date (ISO format or "today")
* `set` (string) - Set number (e.g., "1", "2", "3")
* `reps` (string) - Number of repetitions (e.g., "8", "10")
* `load_lb` (string) - Weight in pounds (e.g., "135", "185")
* `load_kg` (string) - Weight in kilograms (e.g., "60", "100")
* `rir` (string) - Reps in Reserve, 0-10 scale (e.g., "2", "3")
* `rpe` (string) - Rate of Perceived Exertion, 1-10 scale (e.g., "7", "8")
* `notes` (string) - Additional notes

**Schema Rules:**
1. Parameter names are case-sensitive and must match exactly
2. Use `exercise` (NOT `exerciseName`, `movement`, or `name`)
3. Use `load_lb` or `load_kg` (NOT `weight_lb` or `weight_kg`)
4. Use `set`, `reps` exactly as shown (NOT `set_number` or `repetitions`)

**Usage Examples:**
```
[TOOL_CALL: log_set_result(
  exercise: "Bench Press",
  set: "1",
  reps: "8",
  load_lb: "135",
  rir: "2",
  rpe: "8"
)]

[TOOL_CALL: log_set_result(
  exercise: "Back Squat",
  set: "3",
  reps: "5",
  load_kg: "100",
  rir: "1"
)]
```

**Error Prevention:**
* If you get "Missing required parameter 'exercise'" error, check that you used exactly `exercise:` (not `exerciseName:` or `movement:`)
* Exercise name must be specific - "Unknown" is not valid
```

### Step 6: Add Parameter Name Validation Test

Create test to catch regressions:

```swift
// In WorkoutToolExecutor tests
func testStrictParameterNamesEnforced() {
    // Test 1: Wrong parameter name should fail
    let wrongParams = ["exerciseName": "Bench Press", "set": "1"]
    let result = executor.executeTool(ToolCall(name: "log_set_result", parameters: wrongParams))
    XCTAssertFalse(result.success)
    XCTAssertTrue(result.result.contains("Missing required parameter 'exercise'"))
    
    // Test 2: Correct parameter name should succeed
    let correctParams = ["exercise": "Bench Press", "set": "1"]
    let result2 = executor.executeTool(ToolCall(name: "log_set_result", parameters: correctParams))
    XCTAssertTrue(result2.success)
}
```

## Migration Strategy

### For Existing Code
- Old persisted data with `exerciseName` will still decode (backward compatible)
- New data will ONLY be written with canonical names
- No data migration needed - models handle both during read

### For LLM Behavior
**Phase 1 (Immediate):** LLM will get errors when using wrong names
**Phase 2 (Learning):** LLM learns from error messages to use correct schema
**Phase 3 (Stable):** LLM consistently uses correct schema

### Monitoring
Add metrics to track:
- Number of failed `log_set_result` calls due to wrong parameter names
- Most common parameter name mistakes
- Time to LLM adaptation (errors should decrease over sessions)

## Expected Outcomes

### Immediate (Day 1)
- ✅ No more "Unknown" exercise names logged
- ⚠️ May see increased failed tool calls as LLM learns schema
- ✅ Clear error messages guide LLM to correct usage

### Short-term (Week 1)
- ✅ LLM adapts to canonical schema
- ✅ Failed call rate decreases
- ✅ Data quality improves (all entries have valid exercise names)

### Long-term (Month 1+)
- ✅ Zero "Unknown" entries
- ✅ Consistent parameter naming across all tool calls
- ✅ Simplified debugging and maintenance
- ✅ Foundation for future schema evolution

## Rollback Plan

If strict enforcement causes too many issues:

1. **Soft rollback:** Add back ONE alias (e.g., `exerciseName`) with deprecation warning
2. **Full rollback:** Restore all aliases but add logging to track usage patterns
3. **Analysis:** Use logs to understand which aliases LLM actually needs
4. **Retry:** Re-attempt with minimal alias set based on data

## Success Metrics

- 🎯 Zero new "Unknown" exercise entries after deployment
- 🎯 <5% failed `log_set_result` calls after 1 week (LLM adaptation period)
- 🎯 100% of new logged sets use canonical parameter names
- 🎯 Clear, actionable error messages when schema violated

## Files to Modify

1. ✏️ [`WorkoutToolExecutor.swift`](TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift)
   - Lines 87-116: Remove aliases, add strict guard
   - Add helpful error detection for common mistakes

2. ✏️ [`WorkoutSetResult.swift`](TrainerApp/TrainerApp/Models/WorkoutSetResult.swift)
   - Lines 16-30: Remove alias CodingKeys
   - Lines 83-110: Remove alias fallbacks in decoder
   - Lines 56-80: Add validation blacklist for "Unknown"

3. ✏️ [`SystemPrompt.md`](TrainerApp/TrainerApp/SystemPrompt.md)
   - Lines 475-511: Rewrite with strict schema emphasis
   - Add error prevention guidance

4. ➕ Add unit tests for strict schema enforcement