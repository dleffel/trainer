# System Message Temporal Context Implementation Plan

## Overview

Implementation of **Option 2: System Message Time Context** for coach temporal awareness. This approach adds temporal context via system messages while preserving original message content.

## Implementation Approach

### System Message Format
```json
[
  {
    "role": "system", 
    "content": "Current time: 2024-09-14 18:45:23 PDT. Conversation started: 2024-09-14 18:30:15 PDT."
  },
  {"role": "user", "content": "How's my training?"},
  {"role": "assistant", "content": "..."}
]
```

### Benefits
- ✅ Clean separation of temporal data
- ✅ Preserves original message content
- ✅ Easy to add current time context
- ✅ Simple implementation
- ✅ Compatible with existing API format

### Limitations Accepted
- Per-message timing granularity not included (acceptable trade-off)
- System messages consume token budget (~50-100 tokens per request)

## Implementation Steps

### 1. Update LLMClient Message Preparation

**File**: [`TrainerApp/TrainerApp/ContentView.swift`](TrainerApp/TrainerApp/ContentView.swift:751-762)

**Changes needed**:
- Enhance system prompt with temporal context
- Use [`DateProvider`](TrainerApp/TrainerApp/Utilities/DateProvider.swift) for date consistency
- Add timezone information
- Include session duration context

### 2. Modify both LLMClient.complete() and LLMClient.streamComplete()

**Target functions**:
- `LLMClient.complete()` - lines ~700-725
- `LLMClient.streamComplete()` - lines ~728-850

**Implementation**:
```swift
// Enhanced system prompt with temporal context
private static func createTemporalSystemPrompt(
    _ systemPrompt: String, 
    conversationHistory: [ChatMessage],
    currentTime: Date = DateProvider.shared.now
) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    formatter.timeZone = TimeZone.current
    
    let currentTimeString = formatter.string(from: currentTime)
    let sessionStartTime = conversationHistory.first?.date ?? currentTime
    let sessionStartString = formatter.string(from: sessionStartTime)
    
    let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
    let durationMinutes = Int(sessionDuration / 60)
    
    return """
    \(systemPrompt)

    [TEMPORAL_CONTEXT]
    Current time: \(currentTimeString)
    User timezone: \(TimeZone.current.identifier)
    Conversation started: \(sessionStartString)
    Session duration: \(durationMinutes) minutes
    """
}
```

### 3. Integration Points

**ConversationManager Integration**:
- [`ConversationManager.handleStreamingResponse()`](TrainerApp/TrainerApp/Services/ConversationManager.swift:220) 
- [`ConversationManager.handleFollowUpResponse()`](TrainerApp/TrainerApp/Services/ConversationManager.swift:313)

**Key Changes**:
```swift
// Pass conversation history for temporal context
let assistantText = try await LLMClient.streamComplete(
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    history: conversationHistory, // This already includes temporal info
    onToken: { [weak self] token in
        // ... existing logic
    }
)
```

## DateProvider Integration

**Critical Requirement**: Must use [`DateProvider.shared.now`](TrainerApp/TrainerApp/Utilities/DateProvider.swift) instead of `Date()` for consistency with existing date simulation testing.

```swift
// CORRECT - Uses simulated dates when testing
let currentTime = DateProvider.shared.now

// INCORRECT - Would break date simulation
let currentTime = Date()
```

## Token Usage Analysis

**Estimated overhead per request**:
- Current time: ~20 tokens
- Timezone: ~10 tokens  
- Session start: ~20 tokens
- Duration: ~10 tokens
- **Total: ~60 tokens per request**

**Cost impact**: Minimal (~5-8% increase in token usage)

## Success Criteria

1. **Temporal Awareness**: Coach can reference current time accurately
2. **Session Context**: Coach understands conversation duration and timing
3. **DateProvider Compatibility**: Works correctly with simulated dates
4. **API Compatibility**: No breaking changes to OpenRouter integration
5. **Token Efficiency**: <10% overhead in API costs

## Testing Strategy

1. **Unit Tests**: Verify temporal context formatting
2. **Integration Tests**: Test with [`DateProvider`](TrainerApp/TrainerApp/Utilities/DateProvider.swift) simulation
3. **Manual Testing**: Verify coach temporal awareness in responses
4. **Token Monitoring**: Confirm overhead stays within acceptable limits

## Implementation Files

### Primary Changes
- [`TrainerApp/TrainerApp/ContentView.swift`](TrainerApp/TrainerApp/ContentView.swift) - LLMClient methods
- [`TrainerApp/TrainerApp/Services/ConversationManager.swift`](TrainerApp/TrainerApp/Services/ConversationManager.swift) - Integration points

### Dependencies
- [`TrainerApp/TrainerApp/Utilities/DateProvider.swift`](TrainerApp/TrainerApp/Utilities/DateProvider.swift) - Date simulation compatibility
- [`TrainerApp/TrainerApp/Services/ConversationPersistence.swift`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift) - Message timestamps

## Next Steps

1. **Implement LLMClient enhancements** - Add temporal system prompt creation
2. **Update ConversationManager** - Integrate temporal context
3. **Test DateProvider integration** - Verify simulation compatibility  
4. **Validate API compatibility** - Confirm OpenRouter accepts enhanced system prompts
5. **Monitor token usage** - Ensure overhead stays within limits