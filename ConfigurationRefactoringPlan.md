# Configuration Refactoring Plan

## Problem Statement

[`ContentView.swift`](TrainerApp/TrainerApp/ContentView.swift:23-29) still contains business logic that doesn't belong in a UI layer:

```swift
private let model = "openai/gpt-5-mini"  // ❌ Business config in UI
private var systemPrompt: String {       // ❌ Business logic in UI
    SystemPromptLoader.loadSystemPromptWithSchedule()
}
```

The view also directly accesses `UserDefaults` for API keys and passes configuration details (`model`, `systemPrompt`) to `ConversationManager.sendMessage()`.

## Design Principle Violation

**Views should only know about**:
- What to display
- User interactions
- Navigation

**Views should NOT know about**:
- Which AI model to use
- How to load system prompts  
- API configuration details

## Proposed Solution

### Create AppConfiguration Service

**Location**: `TrainerApp/TrainerApp/Services/AppConfiguration.swift`

This service centralizes all app-level configuration:

```swift
class AppConfiguration {
    static let shared = AppConfiguration()
    
    // MARK: - LLM Configuration
    var model: String {
        "openai/gpt-5-mini" // GPT-5 via OpenRouter
    }
    
    var systemPrompt: String {
        SystemPromptLoader.loadSystemPromptWithSchedule()
    }
    
    // MARK: - API Key Management
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "OPENROUTER_API_KEY") }
    }
    
    var hasValidApiKey: Bool {
        !apiKey.isEmpty
    }
}
```

### Update ConversationManager

**Option 1: ConversationManager handles configuration internally**
```swift
class ConversationManager: ObservableObject {
    private let config = AppConfiguration.shared
    private let llmService: LLMServiceProtocol
    
    func sendMessage(_ text: String) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        // ConversationManager now handles config internally
        try await sendMessage(
            text,
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: config.systemPrompt
        )
    }
}
```

**Option 2: Inject configuration into ConversationManager**
```swift
class ConversationManager: ObservableObject {
    private let config: AppConfiguration
    private let llmService: LLMServiceProtocol
    
    init(
        config: AppConfiguration = .shared,
        llmService: LLMServiceProtocol = LLMService.shared
    ) {
        self.config = config
        self.llmService = llmService
    }
    
    // Same as Option 1 - hide config details from caller
    func sendMessage(_ text: String) async throws {
        // ...
    }
}
```

## Detailed Refactoring Steps

### Step 1: Create AppConfiguration.swift

```swift
import Foundation

enum ConfigurationError: LocalizedError {
    case missingApiKey
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Please set your OpenRouter API key in Settings"
        }
    }
}

class AppConfiguration {
    static let shared = AppConfiguration()
    
    private init() {}
    
    // MARK: - LLM Configuration
    
    /// The LLM model to use for chat completions
    var model: String {
        "openai/gpt-5-mini" // GPT-5 via OpenRouter with 128k context
    }
    
    /// Load the system prompt with current schedule context
    var systemPrompt: String {
        SystemPromptLoader.loadSystemPromptWithSchedule()
    }
    
    // MARK: - API Key Management
    
    private let apiKeyKey = "OPENROUTER_API_KEY"
    
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }
    
    var hasValidApiKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

### Step 2: Update ConversationManager

Add a simplified public API that hides configuration:

```swift
@MainActor
class ConversationManager: ObservableObject {
    // ... existing properties ...
    private let config: AppConfiguration
    
    init(
        config: AppConfiguration = .shared,
        llmService: LLMServiceProtocol = LLMService.shared
    ) {
        self.config = config
        self.llmService = llmService
    }
    
    /// Send a message - configuration handled internally
    func sendMessage(_ text: String) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        try await sendMessage(
            text,
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: config.systemPrompt
        )
    }
    
    /// Internal implementation that accepts configuration
    private func sendMessage(
        _ text: String,
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws {
        // Existing implementation
        // ...
    }
}
```

### Step 3: Update ContentView

Simplify to pure UI concerns:

```swift
struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var input: String = ""
    @State private var showSettings: Bool = false
    @State private var showCalendar: Bool = false
    @State private var errorMessage: String?
    @State private var iCloudAvailable = false
    @State private var showMigrationAlert: Bool = false
    
    @EnvironmentObject var navigationState: NavigationState
    
    // UI state only - no business config
    private var messages: [ChatMessage] {
        conversationManager.messages
    }
    
    private var chatState: ChatState {
        conversationManager.conversationState.chatState
    }
    
    // ... UI body ...
    
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        input = ""
        
        do {
            // Clean API - no configuration passed
            try await conversationManager.sendMessage(text)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription 
                ?? error.localizedDescription
        }
    }
}
```

### Step 4: Update SettingsSheet

Use AppConfiguration for API key management:

```swift
private struct SettingsSheet: View {
    private let config = AppConfiguration.shared
    @State private var apiKey: String = AppConfiguration.shared.apiKey
    
    var onSave: () -> Void
    
    var body: some View {
        // ... form ...
        Section("OpenRouter") {
            SecureField("API Key (sk-or-...)", text: $apiKey)
        }
    }
    
    private func saveSettings() {
        config.apiKey = apiKey
        onSave()
    }
}
```

## Benefits

### 1. Separation of Concerns
- ContentView: Pure UI, no configuration knowledge
- AppConfiguration: Centralized config management
- ConversationManager: Handles config internally

### 2. Improved Testability
```swift
// Test with mock configuration
let mockConfig = AppConfiguration()
mockConfig.model = "test-model"
let manager = ConversationManager(config: mockConfig)
```

### 3. Easier Configuration Changes
- Change model in one place (AppConfiguration)
- No need to update UI code
- Configuration can be made dynamic/user-selectable

### 4. Better Error Handling
- Specific `ConfigurationError` types
- Clear error messages
- Validation in one place

## Migration Safety

✅ **Low Risk**:
- Pure code movement and encapsulation
- No logic changes
- Existing tests should pass unchanged
- Build verified at each step

## Implementation Order

1. ✅ Create `AppConfiguration.swift`
2. ✅ Update `ConversationManager` with new API
3. ✅ Update `ContentView` to use simplified API
4. ✅ Update `SettingsSheet` to use AppConfiguration
5. ✅ Build and test
6. ✅ Remove old configuration code from ContentView

## Files to Modify

- ✅ `TrainerApp/TrainerApp/Services/AppConfiguration.swift` (create)
- ✅ `TrainerApp/TrainerApp/Services/ConversationManager.swift` (update)
- ✅ `TrainerApp/TrainerApp/ContentView.swift` (simplify)
- ✅ `TrainerApp/TrainerApp.xcodeproj/project.pbxproj` (add file)

## Result

After this refactoring:
- ContentView: ~500 lines, pure UI
- Business config: AppConfiguration service
- Clean separation: UI ↔ Business ↔ Data