# Chat State Management Plan
## Elegant Solution for Clear User Feedback

## Problem Analysis

### Current Issues
1. **Inconsistent Visual Feedback**
   - Typing indicators appear/disappear unpredictably
   - Empty chat bubbles show up and vanish
   - Tool call syntax ([TOOL_CALL:...]) briefly visible before being cleaned

2. **Missing State Indicators**
   - No feedback during initial API request (before streaming starts)
   - Generic "Checking health data..." for all tool processing
   - No indication of what specific operations are happening

3. **Poor State Transitions**
   - Jarring switches between states
   - No smooth handoff between streaming → tool processing → follow-up

## Proposed Solution: Simple State Machine

### Core Principle
**One source of truth for the entire chat flow state**

### State Enumeration
```swift
enum ChatState {
    case idle
    case preparingResponse        // Initial API call setup
    case streaming(progress: String?)  // Streaming with optional preview text
    case processingTool(name: String, description: String)  // Specific tool feedback
    case finalizing              // Cleaning up response
}
```

### Visual Feedback Strategy

#### 1. State-Driven Status Bar
Instead of multiple indicators, use a single, consistent status component that adapts:

```swift
struct ChatStatusView: View {
    let state: ChatState
    
    var body: some View {
        switch state {
        case .idle:
            EmptyView()
            
        case .preparingResponse:
            StatusBubble(
                icon: "ellipsis.circle",
                text: "Thinking...",
                animated: true
            )
            
        case .streaming(let preview):
            // Show streaming dots with optional preview
            if let preview = preview {
                StatusBubble(
                    icon: "text.bubble",
                    text: preview,
                    animated: true
                )
            } else {
                TypingIndicator()
            }
            
        case .processingTool(let name, let description):
            StatusBubble(
                icon: toolIcon(for: name),
                text: description,
                animated: true
            )
            
        case .finalizing:
            StatusBubble(
                icon: "checkmark.circle",
                text: "Finalizing...",
                animated: false
            )
        }
    }
}
```

#### 2. Tool-Specific Feedback
Map tool names to user-friendly descriptions:

```swift
let toolDescriptions: [String: (icon: String, description: String)] = [
    "get_training_status": ("figure.run", "Checking your training status..."),
    "start_training_program": ("calendar.badge.plus", "Setting up your program..."),
    "plan_week_workouts": ("calendar", "Planning your week..."),
    "generate_workout_instructions": ("doc.text", "Creating workout details..."),
    "get_user_age": ("person.crop.circle", "Checking your profile..."),
    "get_current_week_summary": ("chart.bar", "Getting this week's summary..."),
    "get_metrics_summary": ("chart.line.uptrend.xyaxis", "Analyzing your metrics...")
]
```

### Implementation Changes

#### 1. ContentView State Management
```swift
// Replace multiple booleans with single state
@State private var chatState: ChatState = .idle

// Update send() method to use state transitions
private func send() async {
    // ... initial setup ...
    
    chatState = .preparingResponse
    
    // Start streaming
    chatState = .streaming(progress: nil)
    
    // When tool detected
    if let toolCall = detectedTool {
        chatState = .processingTool(
            name: toolCall.name,
            description: toolDescriptions[toolCall.name]?.description ?? "Processing..."
        )
    }
    
    // Final cleanup
    chatState = .finalizing
    await Task.sleep(for: .milliseconds(200))  // Brief pause for smooth transition
    chatState = .idle
}
```

#### 2. Smart Tool Detection
Intercept tool calls BEFORE they appear in the stream:

```swift
// In streaming callback
onToken: { token in
    // Buffer tokens to detect tool patterns early
    tokenBuffer.append(token)
    
    // Check for tool pattern in buffer
    if let toolMatch = detectToolPattern(in: tokenBuffer) {
        // Don't append tool syntax to visible message
        // Instead, update state
        chatState = .processingTool(name: toolMatch.name, description: ...)
        isBufferingTool = true
    } else if !isBufferingTool {
        // Only append non-tool content
        streamedFullText.append(token)
        updateAssistantMessage(streamedFullText)
    }
}
```

#### 3. Smooth Transitions
Add subtle animations between states:

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    chatState = newState
}
```

### Additional Enhancements

#### 1. Progress Indicators for Long Operations
For operations that might take time, show progress:

```swift
case .processingTool(let name, let description):
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Image(systemName: icon)
                .rotationEffect(.degrees(rotating ? 360 : 0))
            Text(description)
        }
        
        // Optional: Progress bar for known long operations
        if isLongOperation(name) {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }
```

#### 2. Queued Operations Display
When multiple tools will run, show the queue:

```swift
struct ToolQueueView: View {
    let pendingTools: [String]
    let currentTool: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pendingTools, id: \.self) { tool in
                HStack {
                    Image(systemName: tool == currentTool ? "chevron.right.circle.fill" : "circle")
                        .foregroundColor(tool == currentTool ? .blue : .gray)
                    Text(toolDescriptions[tool]?.description ?? tool)
                        .font(.caption)
                        .foregroundColor(tool == currentTool ? .primary : .secondary)
                }
            }
        }
    }
}
```

#### 3. Connection Status
Add network activity indicator:

```swift
struct NetworkActivityView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 4, height: 4)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
```

## Benefits of This Approach

1. **Single Source of Truth**: One state variable controls all UI feedback
2. **Predictable Transitions**: Clear state machine prevents inconsistent UI
3. **Tool Transparency**: Users see exactly what operations are running
4. **No Flashing**: Tool syntax never appears in chat bubbles
5. **Smooth Experience**: Animated transitions between states
6. **Extensible**: Easy to add new states or tool descriptions

## Implementation Priority

1. **Phase 1**: Core state machine and basic status view
2. **Phase 2**: Tool-specific descriptions and icons
3. **Phase 3**: Smart token buffering to hide tool syntax
4. **Phase 4**: Progress indicators and queue display (if needed)

## Testing Scenarios

1. Simple message → response (no tools)
2. Message → tool call → response
3. Multiple tool calls in sequence
4. Tool call with long execution time
5. Network interruption during streaming
6. Rapid message sending

## Success Metrics

- No raw tool syntax ever visible to users
- Clear indication of what's happening at all times
- Smooth visual transitions between states
- Reduced user confusion/anxiety during waits