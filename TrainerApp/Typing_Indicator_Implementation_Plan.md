# Typing Indicator Implementation Plan

## Overview
When the proactive messaging service is processing (evaluating context, calling LLM, executing tools), the app should display a typing indicator if it's currently open. This provides visual feedback that the coach is "thinking" even when the processing happens in the background.

## Requirements
1. Show typing indicator when proactive evaluation starts
2. Keep indicator active during LLM calls and tool execution
3. Hide indicator when message is sent or evaluation completes
4. Handle edge cases (app backgrounded, errors, etc.)
5. Work seamlessly whether app is foreground or background

## Notification Protocol

### Notification Names
```swift
extension Notification.Name {
    static let proactiveCoachTypingStarted = Notification.Name("ProactiveCoachTypingStarted")
    static let proactiveCoachTypingStopped = Notification.Name("ProactiveCoachTypingStopped")
    static let proactiveMessageAdded = Notification.Name("ProactiveMessageAdded")
}
```

### Typing State Enum
```swift
enum ProactiveTypingState {
    case idle
    case evaluating
    case callingLLM
    case executingTools
    case preparingMessage
    
    var displayText: String {
        switch self {
        case .idle: return ""
        case .evaluating: return "Coach is checking in..."
        case .callingLLM: return "Coach is thinking..."
        case .executingTools: return "Coach is preparing..."
        case .preparingMessage: return "Coach is typing..."
        }
    }
}
```

## Implementation Flow

```
┌─────────────────────┐
│ Proactive Check     │
│ Triggered           │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Post Typing Started │──────► ContentView shows indicator
│ Notification        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Evaluate Context    │
│ (Update state)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ LLM Call            │
│ (Update state)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Execute Tools       │
│ (Update state)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Send Message OR     │
│ Decide Not To       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Post Typing Stopped │──────► ContentView hides indicator
│ Notification        │
└─────────────────────┘
```

## Current Architecture Implementation

### ProactiveCoachManager Updates

```swift
// Add to ProactiveCoachManager
private func postTypingNotification(state: ProactiveTypingState) {
    NotificationCenter.default.post(
        name: state == .idle ? .proactiveCoachTypingStopped : .proactiveCoachTypingStarted,
        object: nil,
        userInfo: ["state": state]
    )
}

// Update evaluateAndAct method
private func evaluateAndAct(isTest: Bool = false) async {
    // Start typing indicator
    postTypingNotification(state: .evaluating)
    
    defer {
        // Always stop typing indicator when done
        postTypingNotification(state: .idle)
    }
    
    // ... existing evaluation logic ...
}

// Update askCoachWhatToDo method
private func askCoachWhatToDo(context: CoachContext) async -> CoachDecision {
    // Update state before LLM call
    postTypingNotification(state: .callingLLM)
    
    // ... LLM call logic ...
    
    if !toolResults.isEmpty {
        postTypingNotification(state: .executingTools)
        // ... tool execution ...
    }
    
    postTypingNotification(state: .preparingMessage)
    // ... prepare final decision ...
}
```

## Refactored Architecture Implementation

### ProactiveScheduler Updates

```swift
class ProactiveScheduler {
    // Add typing state management
    private func notifyTypingState(_ state: ProactiveTypingState) {
        NotificationCenter.default.post(
            name: state == .idle ? .proactiveCoachTypingStopped : .proactiveCoachTypingStarted,
            object: nil,
            userInfo: ["state": state]
        )
    }
    
    private func evaluateAndAct(isTest: Bool = false) async {
        notifyTypingState(.evaluating)
        
        defer {
            notifyTypingState(.idle)
        }
        
        // ... evaluation logic ...
    }
}
```

### CoachBrain Updates

```swift
protocol CoachBrainDelegate: AnyObject {
    func coachBrainDidUpdateState(_ state: ProactiveTypingState)
}

class CoachBrain {
    weak var delegate: CoachBrainDelegate?
    
    func evaluateContext(_ context: CoachContext) async throws -> CoachDecision {
        delegate?.coachBrainDidUpdateState(.callingLLM)
        
        // ... LLM logic ...
        
        if !toolResults.isEmpty {
            delegate?.coachBrainDidUpdateState(.executingTools)
            // ... tool execution ...
        }
        
        delegate?.coachBrainDidUpdateState(.preparingMessage)
        // ... prepare decision ...
    }
}
```

## ContentView Integration

```swift
struct ContentView: View {
    @State private var isCoachTyping = false
    @State private var typingMessage = ""
    
    var body: some View {
        VStack {
            // Chat messages...
            
            if isCoachTyping {
                HStack {
                    TypingIndicator()
                    Text(typingMessage)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            setupTypingNotifications()
        }
    }
    
    private func setupTypingNotifications() {
        // Listen for typing start
        NotificationCenter.default.addObserver(
            forName: .proactiveCoachTypingStarted,
            object: nil,
            queue: .main
        ) { notification in
            withAnimation {
                isCoachTyping = true
                if let state = notification.userInfo?["state"] as? ProactiveTypingState {
                    typingMessage = state.displayText
                }
            }
        }
        
        // Listen for typing stop
        NotificationCenter.default.addObserver(
            forName: .proactiveCoachTypingStopped,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation {
                isCoachTyping = false
                typingMessage = ""
            }
        }
    }
}
```

## Typing Indicator View Component

```swift
struct TypingIndicator: View {
    @State private var animationAmount = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount)
                    .opacity(animationAmount)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .onAppear {
            animationAmount = 1.0
        }
    }
}
```

## Edge Case Handling

### 1. App Backgrounded During Processing
```swift
// In AppDelegate or SceneDelegate
func sceneDidEnterBackground(_ scene: UIScene) {
    // Don't need to handle - notifications will queue
    // When app returns, either message is there or typing stopped
}
```

### 2. Error During Processing
```swift
// Ensure typing stops on error
do {
    // ... processing ...
} catch {
    postTypingNotification(state: .idle)
    throw error
}
```

### 3. Multiple Simultaneous Checks
```swift
// Add check to prevent multiple evaluations
private var isEvaluating = false

private func evaluateAndAct(isTest: Bool = false) async {
    guard !isEvaluating else { return }
    isEvaluating = true
    defer { isEvaluating = false }
    // ... rest of method ...
}
```

## Testing Considerations

### Unit Tests
```swift
func testTypingNotificationsSent() async {
    let expectation = XCTestExpectation(description: "Typing notification")
    
    NotificationCenter.default.addObserver(
        forName: .proactiveCoachTypingStarted,
        object: nil,
        queue: nil
    ) { _ in
        expectation.fulfill()
    }
    
    await scheduler.triggerEvaluation()
    
    wait(for: [expectation], timeout: 5.0)
}
```

### UI Tests
```swift
func testTypingIndicatorAppears() {
    // Trigger proactive check
    app.buttons["Test Proactive"].tap()
    
    // Verify typing indicator appears
    XCTAssertTrue(app.staticTexts["Coach is thinking..."].exists)
    
    // Wait for completion
    let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'program'")).firstMatch
    XCTAssertTrue(message.waitForExistence(timeout: 10))
    
    // Verify typing indicator disappears
    XCTAssertFalse(app.staticTexts["Coach is thinking..."].exists)
}
```

## Benefits

1. **User Awareness**: Users know the coach is actively working
2. **Reduced Confusion**: No surprise messages appearing
3. **Professional UX**: Matches chat app expectations
4. **Debugging Aid**: Visual confirmation of background processing
5. **Trust Building**: Shows the app is responsive and working

## Implementation Priority

1. **Phase 1**: Basic typing start/stop notifications
2. **Phase 2**: State-specific messages ("thinking", "preparing", etc.)
3. **Phase 3**: Animated typing indicator component
4. **Phase 4**: Edge case handling and testing

This implementation ensures users always know when their coach is actively processing, whether they triggered it directly or it's happening via proactive scheduling.