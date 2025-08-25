# Tool Call Flow Fix Plan

## Problem
Currently, tool call results are directly substituted into the AI's response text, creating an awkward user experience where raw data appears in brackets. The AI doesn't get a chance to process the tool results and generate a natural response.

## Current Flow (Problematic)
1. User: "Good morning"
2. AI: "Good morning. Let me check your current metrics [TOOL_CALL: get_health_data]"
3. System: Replaces `[TOOL_CALL: get_health_data]` with `[Health Data Retrieved: ...]`
4. User sees: "Good morning. Let me check your current metrics [Health Data Retrieved: Weight: 169.5 lb, ...]"

## Desired Flow
1. User: "Good morning"
2. AI: "Good morning. Let me check your current metrics" + `[TOOL_CALL: get_health_data]`
3. System: Executes tool, gets health data
4. System: Sends tool result back to AI as a system message
5. AI: Generates natural response: "I see you're at 169.5 lbs today with 11.9% body fat..."
6. User sees natural conversation flow

## Implementation Strategy

### Option 1: Multi-Turn Conversation (Recommended)
**Pros:**
- Most natural conversation flow
- AI can contextualize the data properly
- Follows OpenAI's function calling pattern
- Extensible for future tools

**Implementation:**
1. Detect tool calls in AI response
2. Execute tools and collect results
3. Add tool results as a new message in conversation
4. Make another API call for AI to process results
5. Display final natural response

### Option 2: Tool Result Injection
**Pros:**
- Simpler implementation
- Single API call

**Cons:**
- Less natural responses
- Limited AI ability to contextualize

**Implementation:**
1. Pre-process user message to check if tools might be needed
2. Execute tools before API call
3. Include tool results in system prompt or initial context

### Option 3: Streaming with Tool Interruption
**Pros:**
- Real-time feel
- Can show "checking health data..." status

**Cons:**
- Complex implementation
- May require WebSocket or SSE

## Recommended Implementation Details

### 1. Update ToolProcessor
```swift
struct ToolCallResult {
    let toolName: String
    let result: String
    let success: Bool
}

func processResponseWithToolCalls(_ response: String, history: [ChatMessage]) async throws -> (processedResponse: String, requiresFollowUp: Bool, toolResults: [ToolCallResult]?)
```

### 2. Update ContentView.send()
```swift
private func send() async {
    // ... existing code ...
    
    do {
        var conversationHistory = messages
        var finalResponse: String = ""
        var toolExecuted = false
        
        repeat {
            let assistantText = try await LLMClient.complete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: conversationHistory
            )
            
            let (processedText, requiresFollowUp, toolResults) = try await toolProcessor.processResponseWithToolCalls(
                assistantText, 
                history: conversationHistory
            )
            
            if requiresFollowUp, let results = toolResults {
                // Add tool response to conversation
                toolExecuted = true
                
                // Add assistant's partial response (without tool calls)
                if !processedText.isEmpty {
                    conversationHistory.append(ChatMessage(role: .assistant, content: processedText))
                }
                
                // Add tool results as a system message
                let toolResultsMessage = formatToolResults(results)
                conversationHistory.append(ChatMessage(role: .system, content: toolResultsMessage))
                
                // Continue conversation
            } else {
                finalResponse = processedText
                break
            }
        } while toolExecuted && conversationHistory.count < maxTurns
        
        let assistantMsg = ChatMessage(role: .assistant, content: finalResponse)
        messages.append(assistantMsg)
        persist()
    } catch {
        // ... error handling ...
    }
}
```

### 3. Update System Prompt
Add instructions for how to handle tool results:

```
When you receive tool results in a system message:
1. Acknowledge the data naturally in your response
2. Integrate the information into your advice
3. Don't repeat the raw data format
4. Use the data to provide personalized recommendations
```

### 4. Visual Feedback
- Show "Checking health data..." status while tool executes
- Smooth transition between tool execution and final response
- Consider progress indicator for multiple tool calls

## Testing Strategy
1. Test single tool call flow
2. Test multiple tool calls in one response
3. Test error handling (tool failure)
4. Test conversation continuity
5. Test performance with multiple API calls

## Future Enhancements
1. Parallel tool execution for multiple tools
2. Tool call caching to avoid redundant calls
3. User approval for certain tool calls
4. Tool call history/audit log
5. Streaming responses with tool interruption