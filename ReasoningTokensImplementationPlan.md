# Implementation Plan: Display GPT-5 Reasoning Tokens

## Problem

You're using `openapi/gpt-5` (a reasoning model) through OpenRouter, but the app currently doesn't capture or display the model's internal reasoning process. OpenAI's reasoning models expose their "thinking" through special reasoning tokens that are separate from the main response.

## Current State

Looking at [`LLMService.swift`](TrainerApp/TrainerApp/Services/LLMService.swift:73-80), the response structure only captures:
```swift
struct ResponseBody: Codable {
    struct Choice: Codable {
        struct Msg: Codable { 
            let role: String
            let content: String  // ❌ Only captures main content
        }
        let index: Int
        let message: Msg
    }
    let choices: [Choice]
}
```

This misses the reasoning content entirely.

## OpenAI Reasoning Models API Structure

For reasoning models (o1, o3-mini, gpt-5), the API returns:

### Non-Streaming Response:
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "The workout should include...",
      "reasoning_content": "Let me analyze the block context... reviewing last 7 days... bench press was 135lb with RIR 2, so I'll increase to 140lb..."
    }
  }]
}
```

### Streaming Response:
```
data: {"choices":[{"delta":{"reasoning":"Analyzing block context..."}}]}
data: {"choices":[{"delta":{"reasoning":" checking recent workouts..."}}]}
data: {"choices":[{"delta":{"content":"Today's workout..."}}]}
```

### Request Parameters:
To enable reasoning, add to request body:
```json
{
  "model": "openai/gpt-5",
  "include_reasoning": true,  // Enable reasoning capture
  "messages": [...]
}
```

## Implementation Plan

### Phase 1: Update Data Models

**File:** `TrainerApp/TrainerApp/Services/LLMService.swift`

1. **Update Response Structures** (both streaming and non-streaming)
   ```swift
   // Non-streaming
   struct ResponseBody: Codable {
       struct Choice: Codable {
           struct Msg: Codable { 
               let role: String
               let content: String
               let reasoning_content: String?  // ✅ Add this
           }
           let index: Int
           let message: Msg
       }
       let choices: [Choice]
   }
   
   // Streaming
   struct StreamDelta: Codable { 
       let content: String?
       let reasoning: String?  // ✅ Add this
   }
   ```

2. **Update Request Bodies** to include `include_reasoning`
   ```swift
   struct RequestBody: Codable { 
       let model: String
       let messages: [APIMessage]
       let include_reasoning: Bool  // ✅ Add this
   }
   
   struct StreamRequestBody: Codable { 
       let model: String
       let messages: [APIMessage]
       let stream: Bool
       let include_reasoning: Bool  // ✅ Add this
   }
   ```

3. **Update Return Types** to include reasoning
   - Change from `async throws -> String` 
   - To `async throws -> (content: String, reasoning: String?)`

### Phase 2: Update ConversationManager

**File:** `TrainerApp/TrainerApp/Services/ConversationManager.swift`

1. **Add Reasoning Storage** to ChatMessage model
   ```swift
   struct ChatMessage: Codable {
       let id: UUID
       let role: Role
       let content: String
       let reasoning: String?  // ✅ Add this
       let date: Date
   }
   ```

2. **Update sendMessage** to capture reasoning
   ```swift
   let (content, reasoning) = try await llmService.streamComplete(...)
   let assistantMessage = ChatMessage(
       id: UUID(),
       role: .assistant,
       content: content,
       reasoning: reasoning,  // ✅ Store it
       date: Date()
   )
   ```

### Phase 3: Update UI to Display Reasoning

**File:** `TrainerApp/TrainerApp/Views/ChatStateComponents.swift`

1. **Add Reasoning Display** to message bubbles
   - Show reasoning in a collapsible/expandable section
   - Different styling (italic, lighter color, or bordered box)
   - Option to toggle visibility with a setting

**Design Options:**

**Option A: Collapsible "Thinking" Section**
```
┌─────────────────────────────────┐
│ 🧠 Coach's Thinking (tap to expand) │
├─────────────────────────────────┤
│ (collapsed by default)          │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│ Today's Workout:                │
│ Upper Body Strength...          │
└─────────────────────────────────┘
```

**Option B: Inline with Different Styling**
```
┌─────────────────────────────────┐
│ 💭 Reasoning:                   │
│ Reviewing block context... in   │
│ week 3 of Hypertrophy block...  │
│                                 │
│ ─────────────────────────       │
│                                 │
│ Today's Workout:                │
│ Upper Body Strength...          │
└─────────────────────────────────┘
```

**Option C: Toggle Button**
```
┌─────────────────────────────────┐
│ [Show Reasoning] Toggle         │
│                                 │
│ Today's Workout:                │
│ Upper Body Strength...          │
└─────────────────────────────────┘
```

### Phase 4: Add Settings Control

**File:** `TrainerApp/TrainerApp/Debug/DebugMenuView.swift`

1. **Add User Preference**
   ```swift
   Toggle("Show AI Reasoning", 
          isOn: $showReasoning)
   ```

2. **Store in UserDefaults**
   ```swift
   UserDefaults.standard.set(value, forKey: "ShowAIReasoning")
   ```

### Phase 5: Handle Model Compatibility

Not all models support reasoning. Add model detection:

```swift
private func supportsReasoning(model: String) -> Bool {
    let reasoningModels = [
        "openai/o1",
        "openai/o1-preview", 
        "openai/o1-mini",
        "openai/o3-mini",
        "openai/gpt-5"
    ]
    return reasoningModels.contains { model.contains($0) }
}
```

Only add `include_reasoning: true` for compatible models.

## Implementation Steps

### Step 1: Update LLMService (Core)
- [ ] Add `reasoning_content` to response structures
- [ ] Add `reasoning` to streaming delta
- [ ] Add `include_reasoning` to request bodies
- [ ] Update return types to tuples
- [ ] Add model detection for reasoning support

### Step 2: Update ConversationManager
- [ ] Add `reasoning` field to ChatMessage
- [ ] Capture reasoning from LLM responses
- [ ] Store reasoning in conversation history

### Step 3: Update UI
- [ ] Add reasoning display component
- [ ] Implement collapsible/expandable UI
- [ ] Add styling for reasoning text
- [ ] Add toggle setting

### Step 4: Testing
- [ ] Test with gpt-5 model
- [ ] Verify reasoning appears correctly
- [ ] Test collapsible UI works
- [ ] Test with non-reasoning models (should gracefully skip)

## Expected Outcome

After implementation, when the coach plans a workout, you'll see:

```
🧠 Coach's Thinking (tap to view)
├─ Current block: Hypertrophy-Strength, Week 3 of 10
├─ Last bench press: 7 days ago at 135lb (RIR 2)
├─ Progression decision: Increase to 140lb
└─ Weekly balance: Need upper body push work

Today's Workout: Upper Body Strength
- Barbell Bench Press: 4×8 @ 140lb (RIR 2)
- ...
```

This provides full transparency into the coach's decision-making process, showing exactly how it used block context, recent workouts, and past results to plan the workout.

## Recommended Next Steps

Would you like me to:
1. **Implement this feature** - Full implementation with UI
2. **Prototype first** - Just capture reasoning and log it to console to verify it works
3. **Adjust the plan** - Different UI approach or additional features