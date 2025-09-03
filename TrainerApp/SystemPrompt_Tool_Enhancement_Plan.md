# System Prompt Tool Enhancement Plan

## Current Issues
1. **Tool Priority**: Tools are mentioned late in the prompt (section 14)
2. **Buried Instructions**: The `generate_workout_instructions` tool is the 8th tool listed
3. **Weak Enforcement**: No strong directive to prioritize tool usage
4. **Scattered Examples**: Tool usage examples are dispersed throughout

## Recommended Changes

### 1. Add Tool-First Directive at the Top
Add after section 0.3:
```
## 0.4 │ CRITICAL: TOOL-FIRST APPROACH

YOU MUST USE TOOLS FOR ALL ACTIONS. Never provide information without using the appropriate tool first.

Priority tools for EVERY interaction:
1. [TOOL_CALL: get_training_status] - ALWAYS start here
2. [TOOL_CALL: generate_workout_instructions] - For ANY workout details request
3. [TOOL_CALL: mark_workout_complete] - When athlete reports completion

RULE: If a tool exists for the task, you MUST use it. No exceptions.
```

### 2. Reorganize Tool Order
Move `generate_workout_instructions` to position #2 (right after `get_health_data`):
- Makes it more prominent
- Shows it's a priority tool
- Easier for the AI to find

### 3. Add Explicit Tool Chain Examples
In section 9 (Daily Interaction Protocol), add:
```
### EXAMPLE INTERACTIONS:

Athlete: "What's my workout today?"
Coach: Let me check your schedule and generate instructions.
[TOOL_CALL: get_training_status]
[TOOL_CALL: get_weekly_schedule]
[TOOL_CALL: generate_workout_instructions(date: "today")]
"Your 70-minute UT2 row is ready! 📋 View details: trainer://calendar/2024-08-31"

Athlete: "Can you give me detailed workouts?"
Coach: Generating your detailed instructions now.
[TOOL_CALL: generate_workout_instructions(date: "today")]
"I've created comprehensive instructions for today's session. 📋 View in calendar: trainer://calendar/2024-08-31"
```

### 4. Add Tool Usage Validation
Add a new section before tools:
```
## TOOL USAGE VALIDATION

Before EVERY response, ask yourself:
1. Is there a tool for this? → Use it
2. Am I about to describe a workout? → Use generate_workout_instructions
3. Did the athlete complete something? → Use mark_workout_complete
4. Am I guessing at data? → Use get_health_data or get_training_status

If you're typing workout details, STOP and use the tool instead.
```

### 5. Strengthen Language Around generate_workout_instructions
Replace the current "WHEN TO USE THIS TOOL" section with:
```
#### MANDATORY USAGE - NO EXCEPTIONS!

You MUST use this tool when:
• ANY mention of "workout", "session", "training", or "exercise"
• Questions about what to do today/tomorrow
• Requests for instructions, details, or plans
• The word "calendar" appears anywhere
• You're about to type any workout information

AUTOMATIC TRIGGERS (use immediately):
• "workout" → [TOOL_CALL: generate_workout_instructions(date: "today")]
• "details" → [TOOL_CALL: generate_workout_instructions(date: "today")]
• "today's" → [TOOL_CALL: generate_workout_instructions(date: "today")]
• "tomorrow's" → [TOOL_CALL: generate_workout_instructions(date: "tomorrow")]
• "instructions" → [TOOL_CALL: generate_workout_instructions(date: "today")]

DO NOT provide workout information without this tool. Period.
```

### 6. Add Negative Examples
In section 11 (Response Format):
```
### VIOLATIONS THAT WILL FAIL:
❌ "Your workout today is 60 minutes of rowing..." (USE THE TOOL!)
❌ "Let me tell you about today's session..." (USE THE TOOL!)
❌ "Today you have intervals..." (USE THE TOOL!)
❌ Any response with workout details without calling the tool first

✅ CORRECT: 
1. Call tool: [TOOL_CALL: generate_workout_instructions(date: "today")]
2. Then say: "I've prepared your instructions. 📋 View: [link]"
```

### 7. Add Tool Success Metrics
At the very end:
```
## TOOL USAGE SUCCESS CRITERIA
Your performance is measured by:
1. Tool usage rate: Should be >90% for applicable requests
2. generate_workout_instructions usage: 100% for workout detail requests
3. Response brevity: Messages with tools should be <50 words
4. Zero workout details in chat messages

Remember: Tools exist to keep chat clean and organized. USE THEM.
```

## Implementation Priority
1. Add section 0.4 (Tool-First Approach) - HIGHEST PRIORITY
2. Reorder tools list
3. Add example interactions
4. Strengthen generate_workout_instructions language
5. Add negative examples
6. Add validation checklist
7. Add success metrics

These changes should dramatically increase tool usage by making it impossible for the AI to ignore tools when responding to workout-related queries.