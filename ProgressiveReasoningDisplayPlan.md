# Progressive Reasoning Display Implementation Plan

## Problem

Reasoning tokens are streaming in (visible in console), but the UI doesn't display them until the full message is complete. We need progressive display like we have for content tokens.

## Root Cause

In [`ConversationManager.streamResponse()`](TrainerApp/TrainerApp/Services/ConversationManager.swift:369-442), the `onReasoning` callback from [`LLMService.streamComplete()`](TrainerApp/TrainerApp/Services/LLMService.swift:266-269) is provided but NOT IMPLEMENTED.

The `onToken` callback progressively updates UI (lines 386-442), but there's no parallel `onReasoning` handler.

## Solution

Add an `onReasoning` callback handler in the `streamResponse()` method that mirrors the `onToken` pattern.

### Implementation

**File:** `TrainerApp/TrainerApp/Services/ConversationManager.swift`  
**Location:** Inside `streamResponse()` method, after the `onToken` closure (around line 442)

Add this new callback:

```swift
let result = try await llmService.streamComplete(
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    history: apiHistory,
    onToken: { [weak self] token in
        // ... existing onToken implementation (lines 386-442)
    },
    onReasoning: { [weak self] reasoning in
        guard let self = self else { return }
        
        streamedReasoning.append(reasoning)
        
        Task { @MainActor in
            if !messageCreated && !streamedReasoning.isEmpty {
                // Create initial streaming message
                let message = MessageFactory.assistantStreaming(
                    content: streamedContent,
                    reasoning: streamedReasoning
                )
                self.messages.append(message)
                state.setMessageIndex(self.messages.count - 1)
                messageCreated = true
            } else if let idx = state.messageIndex, idx < self.messages.count,
                      self.messages[idx].state == .streaming {
                // Update existing streaming message
                if let updated = self.messages[idx].updatedContent(
                    streamedContent,
                    reasoning: streamedReasoning
                ) {
                    self.messages[idx] = updated
                }
            }
        }
    }
)
```

## Why This Works

1. **Data Flow Already Exists:**
   - [`LLMService`](TrainerApp/TrainerApp/Services/LLMService.swift:266-269) receives reasoning chunks from API
   - `onReasoning` parameter exists in `streamComplete()` signature
   - [`AssistantResponseState`](TrainerApp/TrainerApp/Services/AssistantResponseState.swift) supports reasoning
   - [`MessageFactory`](TrainerApp/TrainerApp/Services/MessageFactory.swift) accepts reasoning parameter

2. **UI Already Reactive:**
   - [`ContentView.swift`](TrainerApp/TrainerApp/ContentView.swift:318-349) displays `message.reasoning`
   - SwiftUI auto-updates when message object changes
   - No UI changes needed

3. **Pattern Already Proven:**
   - The `onToken` handler does exactly this for content
   - Just need to replicate for reasoning

## Testing

1. Send message to GPT-5 model
2. Watch console for reasoning chunks
3. Verify UI updates progressively (not all at once)
4. Confirm reasoning persists after stream completes

## Files Modified

- **Only:** [`TrainerApp/TrainerApp/Services/ConversationManager.swift`](TrainerApp/TrainerApp/Services/ConversationManager.swift:369-442)

## Estimate

15-20 minutes implementation + testing