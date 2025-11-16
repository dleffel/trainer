import Foundation

// MARK: - Configuration Error

enum ConfigurationError: LocalizedError {
    case missingApiKey
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Set your OpenRouter API key in Settings."
        }
    }
}

// MARK: - App Configuration

/// Centralized configuration for the TrainerApp
/// Manages LLM settings, API keys, and other app-level configuration
class AppConfiguration {
    static let shared = AppConfiguration()
    
    private init() {}
    
    // MARK: - LLM Configuration
    
    /// The LLM model to use for chat completions
    var model: String {
        "openai/gpt-5:online" // GPT-5 via OpenRouter with 128k context window
    }
    
    /// Load the system prompt with current schedule context
    var systemPrompt: String {
        SystemPromptLoader.loadSystemPromptWithSchedule()
    }
    
// MARK: - Payload/Reasoning Policies (Balanced preset defaults)
// These can be promoted to user-facing settings later if desired.
enum IncludeImagesPolicy { case latestOnly }

/// Maximum number of recent messages to include in each LLM request
let maxMessagesForRequest: Int = 20

/// Maximum request body size in kilobytes (hard cap)
let maxRequestKB: Int = 200

/// Include reasoning tokens if the model supports it
var includeReasoning: Bool = true

/// Show a live reasoning preview in UI status while streaming
var showReasoningPreview: Bool = true

/// Apply timestamps only to the last K user messages (0 = disabled)
let timestampUserMessagesCount: Int = 3

/// Policy for including images in requests (only the latest attachment-bearing message)
let includeImagesPolicy: IncludeImagesPolicy = .latestOnly
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