# OpenRouter Migration Plan - Switch from OpenAI to OpenRouter with GPT5

## Current State
- **API Endpoint**: `https://api.openai.com/v1/chat/completions`
- **API Key Storage**: `OPENAI_API_KEY` in UserDefaults
- **Model**: `gpt-5` (directly)
- **Implementation**: LLMClient struct in ContentView.swift (lines 880-1030)

## OpenRouter Requirements
- **API Endpoint**: `https://openrouter.ai/api/v1/chat/completions`
- **API Key**: Different from OpenAI (starts with `sk-or-`)
- **Model Format**: `openai/gpt-5` (vendor prefix required)
- **Headers**: 
  - `Authorization: Bearer YOUR_OPENROUTER_API_KEY`
  - `HTTP-Referer: com.yourcompany.TrainerApp` (optional but recommended)
  - `X-Title: TrainerApp` (optional, shows in dashboard)

## Migration Steps

### 1. Update API Configuration
**Files to modify:**
- `ContentView.swift` - Update LLMClient implementation
- `Debug/DebugMenuView.swift` - Update debug references
- `Tests/CoachBrainTests.swift` - Update test references

### 2. API Key Changes
- Change UserDefaults key from `OPENAI_API_KEY` to `OPENROUTER_API_KEY`
- Update all references to the key throughout the codebase
- Update settings view to show "OpenRouter API Key" instead of "OpenAI API Key"

### 3. Code Changes

#### ContentView.swift (LLMClient struct)

**Line 15**: Update API key reference
```swift
@State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY") ?? ""
```

**Line 25**: Update model reference
```swift
private let model = "openai/gpt-5" // OpenRouter format with vendor prefix
```

**Line 180**: Update UserDefaults save
```swift
UserDefaults.standard.set(apiKey, forKey: "OPENROUTER_API_KEY")
```

**Lines 908, 971**: Update API endpoint
```swift
let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
```

**Lines 910-913, 973-977**: Add OpenRouter-specific headers
```swift
request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.addValue("application/json", forHTTPHeaderField: "Content-Type")
request.addValue("com.yourcompany.TrainerApp", forHTTPHeaderField: "HTTP-Referer")
request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
```

#### Debug/DebugMenuView.swift
**Line 349**: Update API display reference
```swift
.replacingOccurrences(of: "openrouter.ai/", with: "")
```

#### Tests/CoachBrainTests.swift
**Lines 28, 140**: Update test API key references
```swift
UserDefaults.standard.removeObject(forKey: "OPENROUTER_API_KEY")
UserDefaults.standard.set("mock-api-key", forKey: "OPENROUTER_API_KEY")
```

### 4. Settings UI Updates
- Update the settings view to display "OpenRouter API Key" label
- Add migration helper to transfer existing OpenAI key (if desired)
- Update placeholder text and help text

### 5. Testing Plan
1. Test basic chat functionality
2. Test streaming responses
3. Test tool calling functionality
4. Verify API logging works correctly
5. Test error handling for invalid API keys
6. Verify timeout handling (120 seconds)

### 6. Migration Helper (Optional)
Create a one-time migration to help users transition:
```swift
// Check if user has old OpenAI key but no OpenRouter key
if let oldKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"),
   UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY") == nil {
    // Prompt user to get OpenRouter API key
    // Clear old key after migration
}
```

## Benefits of OpenRouter
1. **Model Flexibility**: Access to multiple providers through one API
2. **Cost Efficiency**: Potentially lower costs depending on usage
3. **Fallback Options**: Can configure fallback models if primary is unavailable
4. **Usage Analytics**: Better dashboard for tracking usage
5. **Unified Billing**: Single invoice for multiple model providers

## Rollback Plan
If issues arise, reverting requires:
1. Change API endpoint back to `https://api.openai.com/v1/chat/completions`
2. Change model back to `gpt-5` (without vendor prefix)
3. Change UserDefaults key back to `OPENAI_API_KEY`
4. Remove OpenRouter-specific headers

## Notes
- OpenRouter maintains compatibility with OpenAI's chat completion format
- No changes needed to request/response structure
- Tool calling should work identically
- Streaming responses remain unchanged