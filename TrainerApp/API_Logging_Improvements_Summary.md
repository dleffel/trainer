# API Logging System Improvements

## Problem Statement
- API requests were timing out with no clear indication
- Difficult to determine if the LLM was streaming or hung
- API log viewer showed confusing information (unclear if showing request twice or actual response)
- No way to track active/pending requests
- Poor error visibility and debugging capabilities

## Solution: Enhanced API Logging System

### 1. **Enhanced API Logger** (`EnhancedAPILogger.swift`)

#### Key Features:
- **Request Lifecycle Tracking**: Each request gets a unique ID for tracking through its entire lifecycle
- **Timeout Detection**: Automatic 30-second timeout monitoring with clear timeout logging
- **Streaming Support**: Tracks when streaming starts and bytes received
- **Active Request Monitoring**: Maintains a list of currently active requests
- **Better Error Handling**: Captures and logs all error types clearly

#### Implementation Details:
```swift
// Track request start
let requestId = logger.logRequestStart(request)

// Track streaming progress
logger.logStreamingStart(requestId)
logger.logStreamingProgress(requestId, bytesReceived: 1024)

// Log completion
logger.logResponseComplete(requestId, response: response, data: data, error: nil)
```

### 2. **Enhanced Log Entry Structure** (`APILogEntry.swift`)

#### New Fields:
- `phase`: Tracks request state (sent, streaming, completed, failed, timedOut)
- `streamingStatus`: Detailed streaming state
- `bytesReceived`: Tracks data received during streaming
- `isActive`: Computed property for pending requests

#### Request Phases:
1. **Sent** (⏳): Request sent, waiting for response
2. **Streaming** (📥): Response streaming in progress
3. **Completed** (✅): Successfully completed
4. **Failed** (❌): Request failed with error
5. **Timed Out** (⏱️): No response within timeout period

### 3. **Enhanced UI** (`EnhancedAPILogDetailView.swift`)

#### UI Improvements:
1. **Status Banner**: Shows current phase with visual indicators
2. **Timeline View**: Visual representation of request lifecycle
3. **Tab Separation**:
   - Overview: Summary and timeline
   - Request: Headers and body
   - Response: Status, headers, body (shows "waiting" if pending)
   - cURL: Export command

4. **Live Updates**:
   - Auto-refresh for active requests
   - Streaming progress indicator
   - Real-time byte count

### 4. **Usage Integration**

To use the enhanced logging system:

```swift
// Replace existing URLSession calls
let (data, response) = try await session.enhancedLoggingDataTask(with: request)
```

## Benefits

1. **Clear Debugging**: Instantly see if a request is:
   - Waiting for response
   - Streaming data
   - Timed out
   - Failed with specific error

2. **Better Timeout Handling**:
   - Automatic timeout detection
   - Clear timeout messages
   - Configurable timeout duration

3. **Streaming Visibility**:
   - See when streaming starts
   - Track bytes received
   - Know if LLM is actively responding

4. **Improved UI/UX**:
   - Clear visual indicators
   - Separated request/response views
   - Timeline shows exact sequence of events
   - Auto-refresh for live monitoring

## Example Scenarios

### Scenario 1: Timeout Detection
```
Request sent → Waiting 30s → Timeout logged → User notified
Status: "⏱️ Timed out after 30.0s"
```

### Scenario 2: Streaming Response
```
Request sent → Response started → Streaming (2.3 KB received) → Completed
Status: "📥 Streaming... (2.3 KB received)"
```

### Scenario 3: Quick Success
```
Request sent → Response received → Completed
Status: "✅ Completed (200)"
```

## Migration Guide

1. Update logging calls:
   ```swift
   // Old
   session.loggingDataTask(with: request)
   
   // New
   session.enhancedLoggingDataTask(with: request)
   ```

2. Update log viewer references:
   ```swift
   // Old
   APILogDetailView(log: entry)
   
   // New
   EnhancedAPILogDetailView(log: entry)
   ```

3. Enable enhanced logging:
   ```swift
   // In app initialization
   _ = EnhancedAPILogger.shared // Start timeout monitoring
   ```

## Debugging Tips

1. **For Timeouts**: Check the timeline to see exactly when the request was sent
2. **For Streaming Issues**: Look at bytes received to see if data is flowing
3. **For Errors**: Check both the error message and response status code
4. **For Hung Requests**: Active requests show in real-time with elapsed duration

This enhanced system provides complete visibility into API request lifecycle, making debugging significantly easier.