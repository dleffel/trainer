# Workout Instructions Feature - Debug Summary

## Current Status
The detailed workout instructions feature is fully implemented but the coach AI is not calling the tool when requested.

## Implementation Status
✅ **Backend**
- WorkoutDay model extended with `detailedInstructions` field
- `generate_workout_instructions` tool implemented in ToolProcessor
- Tool generates comprehensive workout sections (warm-up, main set, HR zones, etc.)
- Deep linking works with `trainer://calendar/[date]` URLs

✅ **Frontend**
- DetailedInstructionsCard UI component created
- Expandable sections for different instruction types
- Visual indicators (document icon) for days with instructions
- Navigation from chat links to calendar view works

✅ **System Integration**
- URL scheme registered in Info.plist
- NavigationState handles deep link routing
- Calendar view responds to navigation requests

❌ **AI Coach Integration**
- Coach doesn't call the tool when asked for detailed instructions
- System prompt has been updated but AI doesn't follow it

## Test Results
From the logs:
```
User: "Can you give me detailed workouts plz"
Coach: "Let me load your program and push tomorrow's session details to the calendar. One moment...."
ToolProcessor: Found 0 matches (no tool calls)
```

## Fixes Applied
1. **Timeout Issue**: Added 120-second timeout to API requests
2. **System Prompt**: Added explicit triggers and examples for when to use the tool
3. **Proactive Messaging**: Updated CoachBrain to include the tool in proactive flows

## Next Steps
1. **Test with different phrasing** - Try more explicit commands
2. **Add tool to response examples** - Include example conversations in system prompt
3. **Debug LLM decision making** - Add logging to see why tool isn't selected
4. **Consider prompt engineering** - Make tool usage more prominent in instructions

## Quick Test Commands
Try these phrases to trigger the tool:
- "Generate workout instructions for today"
- "Create detailed instructions and save to calendar"
- "Use generate_workout_instructions tool for today"
- "[TOOL_CALL: generate_workout_instructions(date: today)]"

## Workaround
Until the AI reliably calls the tool, users can:
1. Ask explicitly: "Please use the generate_workout_instructions tool"
2. Include tool syntax in their message
3. Navigate to calendar manually to see any generated instructions