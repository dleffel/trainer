# ConversationManager Architecture Refactor Plan

## Executive Summary

This plan addresses the architectural issues in ConversationManager revealed by the reasoning preservation bugs. It proposes a complete refactor to make the code more maintainable, type-safe, and resilient to future feature additions.

---

## Current PR: Immediate Bug Fixes

### Scope
Fix the two reasoning preservation bugs identified in the code review.

### Changes
1. **Line 157:** Add reasoning to conversationHistory
2. **Line 212:** Track and preserve finalReasoning in fallback path
3. **Return Type:** Update `handleStreamingResponse` to return reasoning

### Implementation
See [`ReasoningPreservationBugFix.md`](ReasoningPreservationBugFix.md) for detailed code changes.

### Timeline
- Implementation: 30 minutes
- Testing: 15 minutes
- Ready to merge: Same day

**Status:** Ship this PR first to fix the urgent bugs.

---

## Future PR: Architecture Refactor

### Goals
1. **Centralize state management** - Single source of truth for assistant responses
2. **Type-safe message creation** - Impossible to create messages incorrectly
3. **Eliminate duplication** - Single history, not dual arrays
4. **Simplify flow control** - Clear, testable code paths
5. **Future-proof** - Easy to add new message fields

---

## Phase 1: Extract State Objects (Low Risk)

### 1.1: Create AssistantResponseState

**Purpose:** Encapsulate all assistant response state in one place.

**Location:** New file `TrainerApp/TrainerApp/Services/ConversationManager/AssistantResponseState.swift`

**Implementation:**
```swift
/// Encapsulates the complete state of an assistant's response
struct AssistantResponseState {
    // MARK: - Properties
    
    /// The accumulated content of the response
    private(set) var content: String = ""
    
    /// The accumulated reasoning tokens (optional for non-reasoning models)
    private(set) var reasoning: String? = nil
    
    /// Index in the messages array where this response lives (if created)
    private(set) var messageIndex: Int? = nil
    
    /// Whether the response is complete
    private(set) var isComplete: Bool = false
    
    // MARK: - State Mutations
    
    mutating func appendContent(_ chunk: String) {
        content += chunk
    }
    
    mutating func appendReasoning(_ chunk: String) {
        if reasoning == nil {
            reasoning = chunk
        } else {
            reasoning! += chunk
        }
    }
    
    mutating func setMessageIndex(_ index: Int) {
        messageIndex = index
    }
    
    mutating func markComplete() {
        isComplete = true
    }
    
    // MARK: - Conversions
    
    /// Convert to ChatMessage for UI/persistence
    func toMessage(
        id: UUID = UUID(),
        date: Date = Date.current,
        state: MessageState = .completed
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .assistant,
            content: content,
            reasoning: reasoning,
            date: date,
            state: state
        )
    }
    
    /// Create message for streaming (uses existing ID if available)
    func toStreamingMessage(existingId: UUID? = nil) -> ChatMessage {
        ChatMessage(
            id: existingId ?? UUID(),
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: .streaming
        )
    }
}
```

**Benefits:**
- ✅ Single source of truth for assistant response
- ✅ Guarantees reasoning is never forgotten
- ✅ Type-safe state transitions
- ✅ Clear conversion to ChatMessage
- ✅ Easy to test in isolation

**Migration:** Replace scattered variables in `handleConversationFlow` and `handleStreamingResponse`.

### 1.2: Create MessageFactory

**Purpose:** Centralize all message creation with type-safe builders.

**Location:** New file `TrainerApp/TrainerApp/Services/ConversationManager/MessageFactory.swift`

**Implementation:**
```swift
/// Factory for creating ChatMessage instances with consistent patterns
enum MessageFactory {
    // MARK: - Assistant Messages
    
    static func assistant(
        content: String,
        reasoning: String? = nil,
        state: MessageState = .completed
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: state
        )
    }
    
    static func assistantStreaming(
        content: String,
        reasoning: String? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            reasoning: reasoning,
            state: .streaming
        )
    }
    
    // MARK: - System Messages
    
    static func system(content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
    
    // MARK: - User Messages
    
    static func user(content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
    
    // MARK: - Special Constructors
    
    /// Create from AssistantResponseState
    static func from(_ state: AssistantResponseState, messageState: MessageState = .completed) -> ChatMessage {
        state.toMessage(state: messageState)
    }
    
    /// Update existing message with new content (preserves ID and date)
    static func updated(
        _ message: ChatMessage,
        content: String? = nil,
        reasoning: String? = nil,
        state: MessageState? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            role: message.role,
            content: content ?? message.content,
            reasoning: reasoning ?? message.reasoning,
            date: message.date,
            state: state ?? message.state
        )
    }
}
```

**Benefits:**
- ✅ Consistent message creation everywhere
- ✅ Impossible to forget parameters
- ✅ Clear intent (`.assistant()`, `.system()`)
- ✅ Easy to add validation/logging later
- ✅ Single place to update when adding fields

**Migration:** Replace all `ChatMessage(...)` calls with `MessageFactory.*()`.

---

## Phase 2: Unify History Management (Medium Risk)

### 2.1: Remove Dual Arrays

**Current Problem:**
```swift
@Published var messages: [ChatMessage]        // UI state
var conversationHistory: [ChatMessage]        // API context
```

Two arrays require manual synchronization.

**Solution:** Single source of truth with computed API history.

**Implementation:**
```swift
// MARK: - Message Storage

/// The single source of truth for all messages
@Published private(set) var messages: [ChatMessage] = []

/// Computed property: messages suitable for API context (excludes certain UI-only messages)
private var apiHistory: [ChatMessage] {
    // Only include messages that should go to the API
    messages.filter { message in
        // Exclude incomplete/processing messages
        message.state == .completed
    }
}
```

**Benefits:**
- ✅ No synchronization bugs
- ✅ Clear separation of concerns
- ✅ Computed, always up-to-date
- ✅ Easier to reason about

**Migration:** Replace all `conversationHistory` with `apiHistory`.

### 2.2: Message Management Methods

Create clear methods for message operations:

```swift
// MARK: - Message Management

/// Add a message to UI (and optionally to API history)
private func addMessage(_ message: ChatMessage) {
    messages.append(message)
}

/// Update an existing message by index
private func updateMessage(at index: Int, with message: ChatMessage) {
    guard index < messages.count else { return }
    messages[index] = message
}

/// Update an existing message using its ID
private func updateMessage(id: UUID, updater: (ChatMessage) -> ChatMessage) {
    if let index = messages.firstIndex(where: { $0.id == id }) {
        messages[index] = updater(messages[index])
    }
}

/// Mark message as completed
private func completeMessage(at index: Int) {
    guard index < messages.count else { return }
    messages[index] = messages[index].markCompleted()
}
```

**Benefits:**
- ✅ Clear API for message operations
- ✅ Consistent patterns everywhere
- ✅ Easier to add logging/validation
- ✅ Type-safe operations

---

## Phase 3: Simplify Flow Control (Higher Risk)

### 3.1: Break Down handleConversationFlow

**Current:** One massive 200+ line method with nested logic.

**Solution:** Extract focused, testable methods.

**Structure:**
```swift
// MARK: - Conversation Flow Orchestration

private func handleConversationFlow(...) async throws {
    var responseState = AssistantResponseState()
    var turns = 0
    
    repeat {
        turns += 1
        
        if turns == 1 {
            // Initial response with streaming
            responseState = try await handleInitialResponse(...)
        } else {
            // Follow-up response (non-streaming)
            responseState = try await handleFollowUpTurn(...)
        }
        
        // Check for tool calls
        let toolResult = try await processToolCallsIfNeeded(responseState)
        
        if toolResult.hasTools {
            // Continue loop for assistant's response to tools
            continue
        } else {
            // Finalize and exit
            try await finalizeResponse(responseState)
            break
        }
        
    } while turns < maxConversationTurns
    
    updateState(.idle)
}
```

### 3.2: Extracted Methods

#### handleInitialResponse
```swift
private func handleInitialResponse(
    apiKey: String,
    model: String,
    systemPrompt: String
) async throws -> AssistantResponseState {
    updateState(.streaming(progress: nil))
    
    var state = AssistantResponseState()
    
    // Attempt streaming
    do {
        try await streamResponse(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            into: &state
        )
    } catch {
        // Fallback to non-streaming
        try await fallbackNonStreaming(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            into: &state
        )
    }
    
    return state
}
```

#### processToolCallsIfNeeded
```swift
private struct ToolProcessingResult {
    let hasTools: Bool
    let toolResults: [ToolResult]
    let cleanedResponse: String
}

private func processToolCallsIfNeeded(
    _ responseState: AssistantResponseState
) async throws -> ToolProcessingResult {
    let processed = try await toolProcessor.processResponseWithToolCalls(responseState.content)
    
    if !processed.toolResults.isEmpty {
        // Show tool processing UI
        for result in processed.toolResults {
            updateState(.processingTool(name: result.toolName, description: getToolDescription(result.toolName)))
            try? await Task.sleep(for: .milliseconds(500))
        }
        
        // Update message with cleaned content
        if let idx = responseState.messageIndex {
            updateMessageWithCleanedContent(at: idx, cleanedContent: processed.cleanedResponse, reasoning: responseState.reasoning)
        }
        
        // Add tool results to API history
        let toolMessage = MessageFactory.system(content: toolProcessor.formatToolResults(processed.toolResults))
        addMessage(toolMessage)
        
        return ToolProcessingResult(
            hasTools: true,
            toolResults: processed.toolResults,
            cleanedResponse: processed.cleanedResponse
        )
    }
    
    return ToolProcessingResult(
        hasTools: false,
        toolResults: [],
        cleanedResponse: processed.cleanedResponse
    )
}
```

#### finalizeResponse
```swift
private func finalizeResponse(_ state: AssistantResponseState) async throws {
    guard let idx = state.messageIndex else {
        // No existing message, create one
        let message = MessageFactory.from(state)
        addMessage(message)
        return
    }
    
    // Update existing message
    updateMessage(at: idx) { existing in
        MessageFactory.updated(
            existing,
            content: state.content,
            reasoning: state.reasoning,
            state: .completed
        )
    }
    
    updateState(.finalizing)
    await persistMessages()
}
```

**Benefits:**
- ✅ Each method has single responsibility
- ✅ Easy to test individual pieces
- ✅ Clear flow through orchestrator
- ✅ Easier to understand and maintain
- ✅ Better error handling per section

---

## Phase 4: Streaming Improvements (Medium Risk)

### 4.1: Encapsulate Streaming State

**Current:** Scattered variables for streaming state.

**Solution:** StreamingContext struct.

```swift
private struct StreamingContext {
    var fullText: String = ""
    var reasoning: String = ""
    var tokenBuffer: String = ""
    var isBufferingTool: Bool = false
    var messageCreated: Bool = false
    var messageIndex: Int? = nil
    
    mutating func appendToken(_ token: String) {
        tokenBuffer += token
        if !isBufferingTool {
            fullText += token
        }
    }
    
    mutating func appendReasoning(_ chunk: String) {
        reasoning += chunk
    }
    
    mutating func enterToolBufferMode() {
        isBufferingTool = true
        fullText = tokenBuffer
    }
    
    func toResponseState() -> AssistantResponseState {
        var state = AssistantResponseState()
        state.appendContent(fullText)
        if !reasoning.isEmpty {
            state.appendReasoning(reasoning)
        }
        if let idx = messageIndex {
            state.setMessageIndex(idx)
        }
        return state
    }
}
```

### 4.2: Simplified Streaming Method

```swift
private func streamResponse(
    apiKey: String,
    model: String,
    systemPrompt: String,
    into state: inout AssistantResponseState
) async throws {
    var context = StreamingContext()
    
    let result = try await llmService.streamComplete(
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        history: apiHistory,
        onToken: { [weak self] token in
            context.appendToken(token)
            self?.handleStreamingToken(context: &context)
        },
        onReasoning: { [weak self] reasoning in
            context.appendReasoning(reasoning)
            self?.handleStreamingReasoning(context: &context)
        }
    )
    
    state = context.toResponseState()
}
```

---

## Migration Strategy

### Step 1: Create New Files (No Breaking Changes)
1. Create `AssistantResponseState.swift`
2. Create `MessageFactory.swift`
3. Add unit tests for both

### Step 2: Gradual Adoption (Low Risk)
1. Start using MessageFactory for new message creations
2. Migrate one method at a time to use AssistantResponseState
3. Keep dual arrays temporarily during migration

### Step 3: Refactor Flow (Medium Risk)
1. Extract methods from handleConversationFlow
2. Test each extracted method independently
3. Update orchestrator to use new methods

### Step 4: Cleanup (Final Step)
1. Remove old conversationHistory array
2. Replace all ChatMessage(...) with MessageFactory
3. Remove redundant code
4. Final integration testing

---

## Testing Strategy

### Unit Tests
```swift
class AssistantResponseStateTests: XCTestCase {
    func testContentAccumulation() {
        var state = AssistantResponseState()
        state.appendContent("Hello")
        state.appendContent(" World")
        XCTAssertEqual(state.content, "Hello World")
    }
    
    func testReasoningPreservation() {
        var state = AssistantResponseState()
        state.appendContent("Answer")
        state.appendReasoning("Because...")
        
        let message = state.toMessage()
        XCTAssertEqual(message.content, "Answer")
        XCTAssertEqual(message.reasoning, "Because...")
    }
    
    func testMessageConversion() {
        var state = AssistantResponseState()
        state.appendContent("Test")
        state.appendReasoning("Thinking")
        
        let completed = state.toMessage(state: .completed)
        XCTAssertEqual(completed.state, .completed)
        
        let streaming = state.toStreamingMessage()
        XCTAssertEqual(streaming.state, .streaming)
    }
}

class MessageFactoryTests: XCTestCase {
    func testAssistantMessageCreation() {
        let message = MessageFactory.assistant(
            content: "Hello",
            reasoning: "Test"
        )
        
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Hello")
        XCTAssertEqual(message.reasoning, "Test")
        XCTAssertEqual(message.state, .completed)
    }
    
    func testMessageUpdate() {
        let original = MessageFactory.assistant(content: "Old")
        let updated = MessageFactory.updated(
            original,
            content: "New",
            reasoning: "Added"
        )
        
        XCTAssertEqual(updated.id, original.id) // Preserves ID
        XCTAssertEqual(updated.content, "New")
        XCTAssertEqual(updated.reasoning, "Added")
    }
}
```

### Integration Tests
```swift
class ConversationManagerRefactorTests: XCTestCase {
    func testStreamingWithReasoning() async throws {
        // Test complete streaming flow
        // Verify reasoning preserved throughout
    }
    
    func testToolCallsPreserveReasoning() async throws {
        // Test tool processing doesn't lose reasoning
    }
    
    func testFallbackPathPreservesReasoning() async throws {
        // Test all fallback scenarios
    }
}
```

---

## Risk Assessment

### Low Risk Changes
- ✅ Creating AssistantResponseState (new code)
- ✅ Creating MessageFactory (new code)
- ✅ Adding unit tests

### Medium Risk Changes
- ⚠️ Migrating to use new patterns
- ⚠️ Extracting methods from handleConversationFlow
- ⚠️ Removing dual arrays

### High Risk Changes
- 🚨 Complete flow restructure
- 🚨 Changing streaming architecture

**Recommendation:** Do this incrementally over 2-3 PRs, not all at once.

---

## Timeline Estimate

### PR 1: Foundation (Current PR)
- Bug fixes from code review
- **Duration:** 1 hour
- **Risk:** Low

### PR 2: State Objects
- Create AssistantResponseState
- Create MessageFactory
- Add comprehensive unit tests
- **Duration:** 4-6 hours
- **Risk:** Low (new code only)

### PR 3: Adopt New Patterns
- Migrate handleConversationFlow to use AssistantResponseState
- Replace ChatMessage(...) with MessageFactory
- **Duration:** 6-8 hours
- **Risk:** Medium (refactoring existing code)

### PR 4: Cleanup & Optimization
- Remove dual arrays
- Extract flow methods
- Final integration tests
- **Duration:** 4-6 hours
- **Risk:** Medium

**Total:** 15-21 hours across 4 PRs over 2-3 weeks

---

## Success Criteria

### After Refactor
✅ No reasoning preservation bugs possible (type system prevents it)  
✅ Single source of truth for messages  
✅ All message creation uses MessageFactory  
✅ Methods under 50 lines each  
✅ 90%+ test coverage on new code  
✅ No regression in existing functionality  
✅ Easier to add future message fields  

---

## Conclusion

This refactor transforms ConversationManager from a fragile, hard-to-maintain class into a robust, type-safe architecture. By doing it incrementally over multiple PRs, we minimize risk while improving the codebase.

**Next Steps:**
1. ✅ Ship current PR with bug fixes
2. 📋 Review this plan and adjust as needed
3. 🏗️ Create PR 2 with foundation (State objects + Factory)
4. 🔄 Iterate through remaining PRs