# Message Date Context Enhancement Plan

## Objective
Embed day of week and full date information into each message in the conversation history sent to the LLM, helping it understand temporal context for each message.

## Current State Analysis

### Message Flow
1. **ConversationManager** creates and stores `ChatMessage` objects with timestamps
2. **LLMClient** methods (`complete()` and `streamComplete()`) convert `ChatMessage` objects to API format
3. Currently, only the **system prompt** gets temporal enhancement via `createTemporalSystemPrompt()`
4. Individual message content does **not** include timestamp information

### Relevant Code Locations
- `TrainerApp/TrainerApp/Services/ConversationManager.swift`: Message creation and storage
- `TrainerApp/TrainerApp/ContentView.swift`: 
  - `LLMClient.complete()` (line 644-712)
  - `LLMClient.streamComplete()` (line 715-824)
  - `createTemporalSystemPrompt()` (line 608-642)

### ChatMessage Structure (inferred)
```swift
struct ChatMessage {
    let id: UUID
    let role: MessageRole  // .user, .assistant, .system
    let content: String
    let date: Date  // Already tracked!
    // ... other properties
}
```

## Proposed Solution

### 1. Create Date Formatting Helper Method

Add a new private method to `LLMClient` that formats message timestamps:

```swift
private static func formatMessageTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
}
```

**Format Examples:**
- `"Monday, October 4, 2025 at 2:50 PM PDT"`
- `"Tuesday, October 5, 2025 at 9:15 AM PDT"`

### 2. Create Message Enhancement Helper

Add a method to enhance message content with temporal context:

```swift
private static func enhanceMessageWithTimestamp(
    _ message: ChatMessage
) -> APIMessage {
    let role = switch message.role {
        case .user: "user"
        case .assistant: "assistant"
        case .system: "system"
    }
    
    // Only add timestamps to user and assistant messages
    // System messages should remain unmodified for tool results, etc.
    if message.role == .user || message.role == .assistant {
        let timestamp = formatMessageTimestamp(message.date)
        let enhancedContent = "[\(timestamp)]\n\(message.content)"
        return APIMessage(role: role, content: enhancedContent)
    } else {
        return APIMessage(role: role, content: message.content)
    }
}
```

**Example Output:**
```
[Monday, October 4, 2025 at 2:50 PM PDT]
What workouts should I do this week?
```

### 3. Update LLMClient.complete() Method

Replace the message building loop (lines 676-683) with:

```swift
for m in history {
    msgs.append(enhanceMessageWithTimestamp(m))
}
```

### 4. Update LLMClient.streamComplete() Method

Replace the message building loop (lines 744-751) with:

```swift
for m in history {
    msgs.append(enhanceMessageWithTimestamp(m))
}
```

### 5. Add Debug Logging

Add diagnostic logging to verify the enhancement:

```swift
print("📅 TEMPORAL_DEBUG: Enhanced \(history.count) messages with timestamps")
if let firstMessage = history.first {
    let sample = formatMessageTimestamp(firstMessage.date)
    print("📅 Sample timestamp format: \(sample)")
}
```

## Implementation Details

### Date Formatting Rationale

**Format String: `"EEEE, MMMM d, yyyy 'at' h:mm a zzz"`**
- `EEEE`: Full day name (Monday, Tuesday, etc.)
- `MMMM d, yyyy`: Full month name, day, year (October 4, 2025)
- `h:mm a`: 12-hour time with AM/PM (2:50 PM)
- `zzz`: Timezone abbreviation (PDT, PST, etc.)

**Why This Format:**
1. ✅ Highly readable for LLM
2. ✅ Unambiguous temporal information
3. ✅ Includes timezone for clarity
4. ✅ Natural language format
5. ✅ Consistent with existing temporal prompt format

### Message Selection Strategy

**Enhance:** User and Assistant messages
- These represent the conversation flow
- Timestamps help LLM understand conversation timeline
- Help LLM realize time gaps between interactions

**Don't Enhance:** System messages
- Often contain tool results with specific formatting
- May break tool result parsing
- Less critical for temporal awareness

### Timezone Handling

- Use `TimeZone.current` to match user's local time
- Consistent with `createTemporalSystemPrompt()` approach
- The system prompt already includes `User timezone: \(TimeZone.current.identifier)`

## Benefits

1. **Enhanced Temporal Awareness**: LLM can see exactly when each message was sent
2. **Multi-Day Conversations**: LLM can distinguish messages from different days
3. **Session Boundaries**: Natural breaks in conversation become visible
4. **Time-Sensitive Responses**: LLM can provide appropriate responses based on message age
5. **Consistent with System Prompt**: Complements existing temporal context in system prompt

## Example Before/After

### Before (Current)
```json
{
  "messages": [
    {"role": "user", "content": "Plan my workouts for this week"},
    {"role": "assistant", "content": "I'll create a workout plan..."},
    {"role": "user", "content": "What about tomorrow?"}
  ]
}
```

### After (Enhanced)
```json
{
  "messages": [
    {
      "role": "user", 
      "content": "[Monday, October 4, 2025 at 2:50 PM PDT]\nPlan my workouts for this week"
    },
    {
      "role": "assistant", 
      "content": "[Monday, October 4, 2025 at 2:51 PM PDT]\nI'll create a workout plan..."
    },
    {
      "role": "user", 
      "content": "[Tuesday, October 5, 2025 at 9:15 AM PDT]\nWhat about tomorrow?"
    }
  ]
}
```

## Testing Considerations

1. **Verify Format**: Check that timestamps appear correctly in API logs
2. **Multi-Day Test**: Create messages across different days
3. **Timezone Test**: Verify correct timezone display
4. **Tool Results**: Ensure system messages (tool results) are not modified
5. **API Compatibility**: Confirm OpenRouter accepts the enhanced format

## Code Changes Summary

**Files Modified:**
- `TrainerApp/TrainerApp/ContentView.swift`

**New Methods:**
- `LLMClient.formatMessageTimestamp(_:)` 
- `LLMClient.enhanceMessageWithTimestamp(_:)`

**Modified Methods:**
- `LLMClient.complete()`: Update message building loop
- `LLMClient.streamComplete()`: Update message building loop

**Lines of Code:**
- ~30 lines added
- ~8 lines modified (message building loops)

## Alternative Approaches Considered

### Alternative 1: Add as Separate Metadata Field
❌ OpenRouter API doesn't support custom metadata on messages

### Alternative 2: Add as Message Suffix
❌ Less visible to LLM, prefix is more prominent

### Alternative 3: Add to Every Message Type
❌ Could break tool result parsing in system messages

### Alternative 4: Shorter Format (just date)
❌ Loses time-of-day context which can be important

## Rollout Plan

1. **Phase 1**: Implement helper methods
2. **Phase 2**: Update both LLMClient methods
3. **Phase 3**: Test with API logging enabled
4. **Phase 4**: Verify in multi-day conversation
5. **Phase 5**: Monitor for any issues

## Success Criteria

✅ All user and assistant messages include timestamp prefix  
✅ System messages remain unmodified  
✅ Timestamps are correctly formatted and readable  
✅ LLM can reference specific dates in responses  
✅ No breaking changes to API communication  