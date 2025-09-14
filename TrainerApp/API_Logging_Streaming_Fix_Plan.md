# API Logging Streaming Fix Plan

## Problem Analysis

### Root Cause of Missing Conversation Data

I've identified the core issue: **streaming API calls completely bypass the logging system**, while non-streaming calls have partial logging coverage.

#### Current Architecture Issues:

1. **Streaming Request Logging Gap**: 
   - `LLMClient.streamComplete()` uses `URLSession.shared.bytes(for: request)` directly
   - This bypasses ALL logging systems (both `APILogger` and `EnhancedAPILogger`)
   - Request body is never captured for streaming calls

2. **Streaming Response Logging Gap**:
   - Streaming responses are processed line-by-line via Server-Sent Events (SSE)
   - The assembled response text is never passed to the logging system
   - Only non-streaming calls capture response bodies

3. **Inconsistent Logging Integration**:
   - `LLMClient.complete()` uses `enhancedLoggingDataTask()` + fallback `APILogger.shared.log()`
   - `LLMClient.streamComplete()` has NO logging integration whatsoever

### Current State Analysis:

- **Request Body Empty**: Streaming requests never get their body logged
- **Response Body Missing Conversation**: Streaming responses are never captured
- **Only Works for Non-Streaming**: Simple completion calls work correctly

## Solution Design

### Approach: Integrate Streaming Logging Throughout the Pipeline

#### 1. Enhanced Streaming Logger Integration

Create a streaming-aware logging wrapper that:
- Captures the full request (including body) before streaming starts
- Accumulates streaming response chunks as they arrive
- Logs the complete conversation data after streaming completes

#### 2. Unified Logging Interface

Standardize both streaming and non-streaming calls to use the same logging pipeline:
- Both methods should use consistent logging entry points
- Eliminate duplicate logging calls
- Ensure complete request/response capture

#### 3. Streaming Response Accumulation

Add response accumulation to streaming calls:
- Track streaming chunks as they arrive
- Assemble complete response text
- Log the full conversation after streaming completes

## Implementation Plan

### Phase 1: Create Streaming-Aware Logger Extension

**File**: `TrainerApp/TrainerApp/Extensions/URLSession+StreamingLogging.swift`

Create new extension methods:
```swift
extension URLSession {
    /// Streaming data task with complete API logging
    func streamingLoggingDataTask(
        with request: URLRequest
    ) async throws -> (AsyncSequence, URLResponse, UUID)
    
    /// Complete streaming logging after response assembly
    func completeStreamingLog(
        requestId: UUID,
        fullResponseText: String,
        error: Error?
    )
}
```

### Phase 2: Update LLMClient.streamComplete()

**File**: `TrainerApp/TrainerApp/ContentView.swift` (lines 767-805)

**Changes needed**:
1. Replace `URLSession.shared.bytes(for: request)` with logging-aware version
2. Accumulate full response text for logging
3. Log complete request/response after streaming finishes

**Implementation**:
```swift
// BEFORE streaming starts - log request
let (bytes, resp, requestId) = try await URLSession.shared.streamingLoggingDataTask(with: request)

// DURING streaming - accumulate response
var fullText = ""
for try await line in bytes.lines {
    // ... existing SSE processing logic ...
    fullText += delta
    onToken(delta)
}

// AFTER streaming completes - log complete response
try await URLSession.shared.completeStreamingLog(
    requestId: requestId,
    fullResponseText: fullText,
    error: nil
)
```

### Phase 3: Update LLMClient.complete()

**File**: `TrainerApp/TrainerApp/ContentView.swift` (lines 704-715)

**Changes needed**:
1. Remove duplicate logging calls
2. Use consistent logging with streaming method
3. Eliminate the redundant `APILogger.shared.log()` call

### Phase 4: Enhance EnhancedAPILogger

**File**: `TrainerApp/TrainerApp/Logging/EnhancedAPILogger.swift`

**Add methods**:
```swift
/// Start streaming request with full request body capture
func logStreamingRequestStart(_ request: URLRequest) -> UUID

/// Complete streaming request with full response text
func logStreamingComplete(
    _ requestId: UUID,
    response: URLResponse?,
    fullResponseText: String,
    error: Error?
)
```

### Phase 5: Update APILogEntry for Better Response Display

**File**: `TrainerApp/TrainerApp/Logging/APILogEntry.swift`

**Enhancements**:
- Add computed property to better format conversation JSON
- Improve response body parsing for chat completions
- Add streaming status indicators

## Expected Outcomes

After implementation:

### ✅ Request Body Will Show:
```json
{
  "model": "openai/gpt-5",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant..."
    },
    {
      "role": "user", 
      "content": "Plan my workout for today"
    }
  ],
  "stream": true
}
```

### ✅ Response Body Will Show:
```
I'll help you plan a great workout for today! Let me check your training schedule and create a personalized session.

[TOOL_CALL:get_training_status()]

Based on your current program, here's your workout for today:

**Upper Body Strength Training**
- Bench Press: 4 sets x 8-10 reps
- Pull-ups: 3 sets x 8-12 reps  
- Overhead Press: 3 sets x 8-10 reps
- Rows: 3 sets x 10-12 reps

This targets your chest, back, and shoulders while maintaining progressive overload.
```

### ✅ Complete Conversation Logging:
- Full request/response pairs for all API calls
- Proper streaming response capture
- Tool call conversations preserved
- Debugging information available

## Testing Strategy

### 1. Manual Testing
- Send various conversation types (simple, with tools, long responses)
- Verify request bodies contain complete conversation history
- Confirm response bodies show full AI responses
- Test both streaming and non-streaming paths

### 2. API Log Detail View Verification
- Check that conversation JSON is properly formatted
- Verify response text shows complete AI responses
- Confirm tool calls and responses are captured

### 3. Debug Logging
- Add temporary debug logs to verify data flow
- Confirm response accumulation works correctly
- Validate logging integration points

## Risk Mitigation

### Backward Compatibility
- Keep existing `APILogger` functional as fallback
- Maintain existing log entry format
- Ensure no breaking changes to UI

### Performance Considerations
- Streaming response accumulation has minimal memory impact
- Logging happens asynchronously on background queue
- No impact on real-time streaming performance

### Error Handling
- Graceful degradation if logging fails
- Preserve existing error handling in streaming
- Log partial responses if streaming is interrupted

## Implementation Priority

1. **High Priority**: Phase 1-2 (Core streaming logging)
2. **Medium Priority**: Phase 3-4 (Cleanup and enhancement)  
3. **Low Priority**: Phase 5 (UI improvements)

This plan will completely resolve the missing conversation data issue while improving the overall API logging architecture.