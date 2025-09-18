# SystemPrompt Sections 8.1 & 9 Improvement Plan

## Current Issues Analysis

### Section 8.1 Problems:
- Redundant with section 9.1
- Unclear when to trigger initialization
- Missing error handling scenarios

### Section 9 Problems:
- Calls `get_training_status` twice (steps 1 & 2)
- Uses `get_weekly_schedule` incorrectly to check today's workout
- No clear decision flowchart
- Scattered logic across multiple subsections

## Proposed Solution

### 1. Consolidate and Restructure

**New Section 8.1: Program Initialization**
- Single, clear initialization protocol
- Remove redundancy with section 9
- Add clear conditions for when initialization is needed

**New Section 9: Session Start Protocol**
- Single decision flowchart
- Eliminate redundant tool calls
- Clear conditional logic with proper tool usage

### 2. Improved Structure Design

```
8 │ PROGRAM INITIALIZATION
8.1 │ FIRST-TIME SETUP PROTOCOL
    ├── When to Initialize
    ├── Initialization Steps  
    └── Validation

9 │ SESSION START PROTOCOL
9.1 │ EVERY SESSION WORKFLOW
    ├── Decision Flowchart
    ├── Tool Usage Rules
    └── Common Scenarios
```

## Detailed Improvements

### Section 8.1: Program Initialization
**Purpose**: Handle first-time program setup only

```markdown
### 8.1 │ FIRST-TIME SETUP PROTOCOL

**When to Initialize:**
- At very start of coaching relationship
- When `get_training_status` returns "No active training program"
- When program has expired/completed

**Initialization Steps:**
1. [TOOL_CALL: start_training_program(macroCycle: 1)]
2. Announce: "I've initialized your 20-week training program starting with the Hypertrophy-Strength block."
3. [TOOL_CALL: plan_workout] to generate first day's workout

**Critical Rule**: Never leave athlete without an active program or today's workout plan.
```

### Section 9: Session Start Protocol
**Purpose**: Handle every coaching session interaction

```markdown
## 9 │ SESSION START PROTOCOL

### 9.1 │ EVERY SESSION WORKFLOW

**Decision Flowchart:**
```
START
  ↓
[TOOL_CALL: get_training_status]
  ↓
Program exists? 
  ├─ NO → Go to Section 8.1 (Initialize Program)
  └─ YES → Continue below
  ↓
[TOOL_CALL: get_workout(date: "today")]
  ↓
Today's workout exists?
  ├─ NO → [TOOL_CALL: plan_workout] 
  └─ YES → Review workout with athlete
```

**Tool Usage Rules:**
- `get_training_status`: Check program existence & current phase
- `get_workout(date: "today")`: Check if today's workout is planned
- `plan_workout`: Create structured workout for specific date
- `get_weekly_schedule`: Only when athlete asks about the full week

**Common Scenarios:**
1. **New athlete**: Initialize → Plan today's workout
2. **Returning athlete**: Check status → Verify today's workout exists
3. **No today's workout**: Plan immediately using current phase
```

## Implementation Steps

1. **Replace Section 8.1** with consolidated initialization protocol
2. **Replace Section 9** with clear decision flowchart
3. **Add tool usage rules** to eliminate confusion
4. **Remove redundant sections** (current 9.1 content)
5. **Test logic flow** to ensure no gaps

## Key Benefits

✅ **Eliminates redundancy** between sections 8.1 and 9
✅ **Clear decision points** with visual flowchart
✅ **Proper tool usage** - no more wrong tool for wrong purpose
✅ **Single source of truth** for each protocol
✅ **Scannable format** for quick reference during coaching

## Validation Checklist

- [ ] No redundant tool calls
- [ ] Clear conditional logic
- [ ] Proper tool usage for each scenario
- [ ] Complete coverage of all cases
- [ ] Easy to follow decision tree
- [ ] Maintains all current functionality

## Next Steps

1. Implement the new sections in SystemPrompt.md
2. Validate the logical flow
3. Test with common coaching scenarios
4. Ensure consistency with rest of system prompt