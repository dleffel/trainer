# Workout Instructions Feature - Timeout Debugging

## Issue
The OpenAI API is timing out when the proactive coach tries to make LLM calls.

## Current Configuration
- **Model**: `gpt-5` (primary), `gpt-5-mini` (follow-up)
- **API Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Timeout**: Now set to 120 seconds (was using default ~60s)

## Error Details
```
Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
```

## Code Locations
1. **CoachBrain.swift** (lines 66, 84): Uses `gpt-5` and `gpt-5-mini` models
2. **ContentView.swift** (line 25): Uses `gpt-5` model
3. **ContentView.swift** (line 724): Added `request.timeoutInterval = 120.0`

## Debugging Steps Taken
1. ✅ Identified the models being used
2. ✅ Located the LLMClient implementation
3. ✅ Added explicit timeout of 120 seconds
4. ✅ Confirmed the coach is attempting to call the new `generate_workout_instructions` tool

## Possible Causes
1. **Network Issues**: The simulator might have network connectivity problems
2. **API Response Time**: The `gpt-5` model might be taking longer than expected
3. **Request Size**: The system prompt + context might be creating a very large request
4. **API Availability**: The custom API endpoint might be experiencing issues

## Next Steps to Debug
1. **Test with a simpler model**: Temporarily change to `gpt-4` or `gpt-3.5-turbo` to see if it's model-specific
2. **Check request size**: Log the actual request payload size
3. **Test API directly**: Use curl to test the API endpoint directly
4. **Add request logging**: Log the full request details before sending
5. **Check network**: Verify simulator has internet access

## Quick Test Command
```bash
curl -X POST https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Temporary Workaround
If the timeout persists, consider:
1. Using a faster model temporarily
2. Reducing the system prompt size
3. Implementing request retry logic
4. Using streaming responses instead of waiting for completion