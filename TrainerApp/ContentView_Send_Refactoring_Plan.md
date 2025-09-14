# ContentView Send Method Refactoring Plan

## Problem Analysis

The `ContentView.send()` method is a 60+ line monolith that violates multiple SOLID principles:

### Current Issues
- **Single Responsibility Violation**: Handles UI, business logic, streaming, tools, persistence
- **Open/Closed Violation**: Adding new features requires modifying this massive method
- **Dependency Inversion Violation**: View directly manages complex business operations
- **High Cyclomatic Complexity**: Multiple nested conditions and state management
- **Poor Testability**: Business logic tightly coupled to SwiftUI view

### Lines of Code Analysis
- **Total**: 60+ lines (continues beyond line 500)
- **UI Logic**: ~15 lines (state management, input handling)
- **Business Logic**: ~45+ lines (conversation flow, streaming, tools)

## Proposed Solution: Extract ConversationManager

### New Service: `ConversationManager`

#### Primary Responsibilities
- Manage conversation flow and state
- Coordinate message creation and history
- Handle streaming response coordination
- Orchestrate tool processing
- Manage conversation persistence
- Provide conversation state updates to UI

#### Interface Design
```swift
@MainActor
class ConversationManager: ObservableObject {
    // State
    @Published var conversationState: ConversationState = .idle
    @Published var messages: [ChatMessage] = []
    
    // Core Methods
    func sendMessage(_ text: String, apiKey: String, systemPrompt: String) async throws
    func loadConversation() async
    func clearConversation() async
    
    // Streaming Coordination
    private func handleStreamingResponse(...) async throws
    private func processToolCalls(...) async throws
    private func updateConversationState(_ state: ConversationState)
}

enum ConversationState {
    case idle
    case preparingResponse
    case streaming(progress: String?)
    case processingTools(toolName: String)
    case error(String)
}
```

### Refactoring Steps

1. **Create ConversationManager Service**
   - Extract conversation state management
   - Move message creation and history logic
   - Implement streaming coordination
   - Add tool processing orchestration
   - Include persistence handling

2. **Update ContentView**
   - Replace direct business logic with ConversationManager calls
   - Inject ConversationManager dependency
   - Simplify send() to focus on UI concerns only
   - Map ConversationState to ChatState for UI

3. **Preserve All Functionality**
   - Maintain exact streaming behavior
   - Keep tool processing integration
   - Preserve error handling patterns
   - Maintain conversation persistence

### Before/After Comparison

#### Before (ContentView.send())
```swift
private func send() async {
    // 60+ lines of mixed UI and business logic
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    guard !apiKey.isEmpty else { /* error handling */ }
    
    input = ""
    let userMsg = ChatMessage(role: .user, content: text)
    messages.append(userMsg)
    persist()
    
    withAnimation(.easeInOut(duration: 0.3)) {
        chatState = .preparingResponse
    }
    
    // ... 45+ more lines of complex business logic
}
```

#### After (ContentView.send())
```swift
private func send() async {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    guard !apiKey.isEmpty else {
        errorMessage = "Set your OpenAI API key in Settings."
        return
    }
    
    input = ""
    
    do {
        try await conversationManager.sendMessage(
            text,
            apiKey: apiKey,
            systemPrompt: systemPrompt
        )
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

### Benefits

1. **Separation of Concerns**
   - UI logic stays in ContentView
   - Business logic moves to ConversationManager
   - Clear responsibility boundaries

2. **Improved Testability**
   - ConversationManager can be unit tested
   - Mock streaming and tool responses
   - Test conversation flow independently

3. **Enhanced Maintainability**
   - Changes to conversation logic don't affect UI
   - New features have a clear home
   - Reduced complexity in ContentView

4. **Better Architecture**
   - Follows MVVM pattern properly
   - Enables future conversation features
   - Supports multiple conversation instances

### Implementation Details

#### State Mapping
```swift
// ContentView maps ConversationState to existing ChatState
private var chatState: ChatState {
    switch conversationManager.conversationState {
    case .idle: return .idle
    case .preparingResponse: return .preparingResponse
    case .streaming(let progress): return .streaming(progress: progress)
    case .processingTools(let toolName): return .toolState(for: toolName)
    case .error: return .idle // Handle via errorMessage
    }
}
```

#### Message Synchronization
```swift
// ContentView observes ConversationManager messages
private var messages: [ChatMessage] {
    conversationManager.messages
}
```

### Risk Assessment
- **Low Risk**: Focused extraction without external API changes
- **High Value**: Significant architectural improvement
- **Backward Compatible**: All existing behavior preserved
- **Testable**: New service can be thoroughly unit tested

### Success Criteria
- [ ] ConversationManager created with clear responsibilities
- [ ] ContentView.send() reduced to ~15 lines
- [ ] All streaming functionality preserved
- [ ] Tool processing continues to work
- [ ] Conversation persistence maintained
- [ ] Unit tests added for ConversationManager
- [ ] Build passes without warnings
- [ ] UI behavior unchanged from user perspective

## Next Potential Improvements
After this refactoring establishes the pattern:
1. Extract streaming logic to StreamingCoordinator
2. Create MessageValidator service
3. Extract persistence to ConversationRepository
4. Create ToolOrchestrator service