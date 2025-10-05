# LLM Client Refactoring Plan

## Problem Statement

[`ContentView.swift`](TrainerApp/TrainerApp/ContentView.swift:606-873) currently contains an `LLMClient` enum that makes direct API calls to OpenRouter. This violates separation of concerns and creates several issues:

1. **UI Layer Contamination**: ContentView is a SwiftUI view that should only handle presentation logic, not API calls
2. **Poor Testability**: Cannot easily mock or test API interactions
3. **Tight Coupling**: ConversationManager is forced to depend on code embedded in a view file
4. **Violates Single Responsibility**: ContentView has too many responsibilities (UI + API client + error handling)
5. **Inconsistent Architecture**: Other services (CoachBrain, ToolProcessor, etc.) are properly separated in `Services/`

## Current Architecture

```
ContentView.swift (882 lines)
├── UI Components (View body, input bar, etc.)
├── LLMClient enum (267 lines) ❌ WRONG PLACE
│   ├── complete() - Non-streaming API calls
│   ├── streamComplete() - Streaming API calls
│   ├── Temporal system prompt enhancement
│   └── Message timestamp formatting
└── LLMError enum

ConversationManager.swift
├── Calls LLMClient.streamComplete() (line 220)
├── Calls LLMClient.complete() (lines 285, 331)
└── Depends on ContentView.swift ❌ WRONG DEPENDENCY
```

## Proposed Architecture

```
Services/
├── LLMService.swift (NEW)
│   ├── LLMClient class (moved from ContentView)
│   ├── LLMError enum (moved from ContentView)
│   └── Protocol for testability
└── ConversationManager.swift
    └── Uses LLMService ✅ PROPER DEPENDENCY

ContentView.swift
└── UI only ✅ CLEAN SEPARATION
```

## Detailed Refactoring Steps

### Step 1: Create LLMService.swift

**Location**: `TrainerApp/TrainerApp/Services/LLMService.swift`

**Contents**:
```swift
import Foundation

// MARK: - Error Types

enum LLMError: LocalizedError {
    case missingContent
    case invalidResponse
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .missingContent: return "No content returned by the model."
        case .invalidResponse: return "Unexpected response from the model."
        case .httpError(let code): return "Network error: HTTP \(code)."
        }
    }
}

// MARK: - Protocol for Dependency Injection

protocol LLMServiceProtocol {
    func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> String
    
    func streamComplete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> String
}

// MARK: - LLM Service Implementation

class LLMService: LLMServiceProtocol {
    // Singleton for convenience, but protocol allows dependency injection
    static let shared = LLMService()
    
    private init() {}
    
    // [Move all LLMClient methods here]
    // - complete()
    // - streamComplete()
    // - createTemporalSystemPrompt()
    // - enhanceMessageWithTimestamp()
    // - formatMessageTimestamp()
    // - messageTimestampFormatter
}
```

### Step 2: Update ConversationManager

**File**: `TrainerApp/TrainerApp/Services/ConversationManager.swift`

**Changes**:
1. Add dependency injection property:
   ```swift
   private let llmService: LLMServiceProtocol
   ```

2. Update initializer:
   ```swift
   init(llmService: LLMServiceProtocol = LLMService.shared) {
       self.llmService = llmService
   }
   ```

3. Replace all `LLMClient` calls with `llmService`:
   - Line 220: `LLMClient.streamComplete(...)` → `llmService.streamComplete(...)`
   - Line 285: `LLMClient.complete(...)` → `llmService.complete(...)`
   - Line 331: `LLMClient.complete(...)` → `llmService.complete(...)`

### Step 3: Clean Up ContentView

**File**: `TrainerApp/TrainerApp/ContentView.swift`

**Removals**:
1. Delete lines 592-604: `LLMError` enum
2. Delete lines 606-873: `LLMClient` enum
3. Keep only UI-related code

**File should reduce from 882 lines to ~600 lines**

### Step 4: Update Xcode Project

Add `LLMService.swift` to the Xcode project:
1. Right-click on `Services/` folder in Xcode
2. Add New File → Swift File
3. Name: `LLMService.swift`
4. Target: TrainerApp
5. Group: Services

### Step 5: Testing & Validation

1. **Build Verification**:
   ```bash
   xcodebuild -project TrainerApp/TrainerApp.xcodeproj -scheme TrainerApp build
   ```

2. **Manual Testing**:
   - Send a chat message
   - Verify streaming works
   - Test tool calls
   - Confirm error handling

3. **Create Mock for Testing**:
   ```swift
   class MockLLMService: LLMServiceProtocol {
       var completeResponse: String = ""
       var shouldThrowError: LLMError?
       
       func complete(...) async throws -> String {
           if let error = shouldThrowError { throw error }
           return completeResponse
       }
       
       func streamComplete(...) async throws -> String {
           if let error = shouldThrowError { throw error }
           // Simulate streaming by calling onToken
           for char in completeResponse {
               onToken(String(char))
           }
           return completeResponse
       }
   }
   ```

## Benefits of This Refactoring

### 1. Separation of Concerns
- ContentView focuses only on UI presentation
- LLMService handles all API interactions
- Clear boundaries between layers

### 2. Improved Testability
- Can inject mock LLMService for testing ConversationManager
- No need to depend on actual API or ContentView
- Easier to test error scenarios

### 3. Better Maintainability
- LLM logic centralized in one service
- Changes to API client don't affect UI code
- Follows existing project patterns (Services/)

### 4. Reusability
- LLMService can be used by other components
- Not tied to specific UI implementation
- Protocol allows for different implementations

### 5. Consistent Architecture
- Follows same pattern as CoachBrain, ToolProcessor, etc.
- Services layer properly separated from Views layer
- Dependency injection ready

## Migration Safety

This is a **safe refactoring** because:
1. ✅ Pure code movement - no logic changes
2. ✅ Maintains exact same API interfaces
3. ✅ No changes to external behavior
4. ✅ Can be tested incrementally
5. ✅ Easy to revert if needed

## Implementation Order

1. Create `LLMService.swift` with all moved code
2. Update `ConversationManager.swift` to use new service
3. Clean up `ContentView.swift` (remove old code)
4. Build and test thoroughly
5. Commit changes

## Related Files to Update

- ✅ `TrainerApp/TrainerApp/Services/LLMService.swift` (create)
- ✅ `TrainerApp/TrainerApp/Services/ConversationManager.swift` (update)
- ✅ `TrainerApp/TrainerApp/ContentView.swift` (clean up)
- ✅ `TrainerApp/TrainerApp.xcodeproj/project.pbxproj` (add file reference)

## Testing Checklist

- [ ] App builds successfully
- [ ] Chat messages send correctly
- [ ] Streaming responses work
- [ ] Tool calls execute properly
- [ ] Error handling works
- [ ] API logging still functions
- [ ] Temporal context enhancement preserved
- [ ] Message timestamps still formatted correctly

## Notes

- The LLMClient code is well-structured and doesn't need changes
- This is purely an organizational refactoring
- Protocol-based design enables future extensions (e.g., different LLM providers)
- Maintains all existing functionality including:
  - Temporal system prompt enhancement
  - Message timestamp formatting  
  - API logging integration
  - Streaming with URLSession extensions