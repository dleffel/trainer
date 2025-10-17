import Foundation
import SwiftUI
import UIKit

/// Manages conversation flow, message handling, and coordination between streaming, tools, and persistence
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var conversationState: ConversationState = .idle
    
    // Reasoning preview state for UI
    @Published private(set) var isStreamingReasoning: Bool = false
    @Published private(set) var latestReasoningChunk: String? = nil
    
    // MARK: - Private Properties
    private let persistence = ConversationPersistence()
    private let config: AppConfiguration
    private let logger = ConversationLogger.shared
    
    // MARK: - Coordinators
    private let streamingCoordinator: StreamingCoordinator
    private let toolCoordinator: ToolExecutionCoordinator
    private let responseOrchestrator: ResponseOrchestrator
    
    // MARK: - Computed Properties
    
    /// Computed property: messages suitable for API context
    /// This replaces the previous dual-array pattern (messages + conversationHistory)
    private var apiHistory: [ChatMessage] {
        messages.filter { message in
            // Only include completed messages in API history
            message.state == .completed
        }
    }
    
    // MARK: - Initialization
    
    init(
        config: AppConfiguration = .shared,
        llmService: LLMServiceProtocol = LLMService.shared
    ) {
        self.config = config
        
        // Initialize coordinators
        self.streamingCoordinator = StreamingCoordinator(llmService: llmService)
        self.toolCoordinator = ToolExecutionCoordinator()
        self.responseOrchestrator = ResponseOrchestrator(
            streamingCoordinator: streamingCoordinator,
            toolCoordinator: toolCoordinator,
            llmService: llmService
        )
        
        // Set up delegates
        self.streamingCoordinator.delegate = self
        self.toolCoordinator.delegate = self
        self.responseOrchestrator.delegate = self
    }
    
    // MARK: - Public Interface
    
    /// Initialize and load existing conversation
    func initialize() async {
        await loadConversation()
    }
    
    /// Send a message - configuration handled internally
    func sendMessage(_ text: String, images: [UIImage] = []) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        try await sendMessageWithConfig(
            text,
            images: images,
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: config.systemPrompt
        )
    }
    
    /// Internal implementation with explicit configuration (for testing/flexibility)
    private func sendMessageWithConfig(_ text: String, images: [UIImage], apiKey: String, model: String, systemPrompt: String) async throws {
        // Create and add user message using MessageFactory
        let userMessage = images.isEmpty
            ? MessageFactory.user(content: text)
            : MessageFactory.userWithImages(content: text, images: images)
        
        messages.append(userMessage)
        await persistMessages()
        
        // Start conversation flow via orchestrator
        updateState(.preparingResponse)
        
        do {
            let result = try await responseOrchestrator.executeConversationFlow(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt
            )
            
            logger.log(ConversationLogger.LogLevel.info, "Conversation completed in \(result.turns) turns, hadTools: \(result.hadTools)", context: "sendMessage")
            
            // Persist after successful completion
            await persistMessages()
            
        } catch {
            logger.logError(error, context: "sendMessage")
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    /// Load conversation from persistence
    func loadConversation() async {
        do {
            messages = try persistence.load()
        } catch {
            logger.logError(error, context: "loadConversation")
            messages = []
        }
    }
    
    /// Clear all messages and persistence
    func clearConversation() async {
        messages.removeAll()
        do {
            try persistence.clear()
        } catch {
            logger.logError(error, context: "clearConversation")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Generate meaningful response content from tool results
    private func generateMeaningfulResponseContent(from history: [ChatMessage]) -> String {
        let recentSystemMessages = history.suffix(3).filter { $0.role == .system }
        var responseComponents: [String] = []
        
        for message in recentSystemMessages {
            if message.content.contains("[Structured Workout Planned]") {
                let lines = message.content.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("• Workout: ") || line.contains("• Exercises: ") || line.contains("• Duration: ") {
                        responseComponents.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            
            if message.content.contains("[Training Status]") || message.content.contains("Current Block:") {
                responseComponents.append("I've checked your training status and you're all set!")
            }
            
            if message.content.contains("Hypertrophy-Strength") {
                responseComponents.append("You're in the Hypertrophy-Strength phase - perfect for building strength.")
            }
        }
        
        return responseComponents.isEmpty
            ? "Great! I've completed the requested actions and everything is set up for you."
            : "Perfect! I've completed the setup:\n\n" + responseComponents.joined(separator: "\n")
    }
    
    /// Update conversation state with animation
    private func updateState(_ newState: ConversationState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            conversationState = newState
        }
    }
    
    /// Persist messages to storage
    private func persistMessages() async {
        do {
            try persistence.save(messages)
            logger.logPersistence("save", messageCount: messages.count)
        } catch {
            logger.logError(error, context: "persistMessages")
        }
    }
}

// MARK: - Conversation State

/// Represents the current state of the conversation
enum ConversationState: Equatable {
    case idle
    case preparingResponse
    case streaming(progress: String?)
    case processingTool(name: String, description: String)
    case finalizing
    case error(String)
}

// MARK: - State Mapping Extension

extension ConversationState {
    /// Map ConversationState to ChatState for UI compatibility
    var chatState: ChatState {
        switch self {
        case .idle:
            return .idle
        case .preparingResponse:
            return .preparingResponse
        case .streaming(let progress):
            return .streaming(progress: progress)
        case .processingTool(let name, let description):
            return .processingTool(name: name, description: description)
        case .finalizing:
            return .finalizing
        case .error:
            return .idle // Handle errors via separate error message in UI
        }
    }
}

// MARK: - StreamingStateDelegate

extension ConversationManager: StreamingStateDelegate {
    func streamingDidCreateMessage(_ message: ChatMessage) -> Int {
        // Append the message and return its index
        messages.append(message)
        let index = messages.count - 1
        logger.log(ConversationLogger.LogLevel.debug, "Streaming message created at index \(index)", context: "Streaming")
        return index
    }
    
    func streamingDidUpdateMessage(at index: Int, with message: ChatMessage) {
        // Update our messages array with the latest version
        if index < messages.count {
            messages[index] = message
        }
    }
    
    func streamingDidDetectTool(name: String, description: String) {
        updateState(.processingTool(name: name, description: description))
    }
    
    func streamingDidUpdateReasoningState(isStreaming: Bool, latestChunk: String?) {
        self.isStreamingReasoning = isStreaming
        self.latestReasoningChunk = latestChunk
    }
}

// MARK: - ToolExecutionStateDelegate

extension ConversationManager: ToolExecutionStateDelegate {
    func toolExecutionDidStart(toolName: String, description: String) {
        // Clear reasoning preview flags before tool processing
        self.isStreamingReasoning = false
        self.latestReasoningChunk = nil
func toolExecutionDidStart(toolName: String, description: String) {
    self.isStreamingReasoning = false
    self.latestReasoningChunk = nil
    updateState(.processingTool(name: toolName, description: description))
}
    }
    
    func toolExecutionDidComplete(result: ToolProcessor.ToolCallResult) {
        logger.log(ConversationLogger.LogLevel.info, "Tool '\(result.toolName)' completed: \(result.success)", context: "ToolExecution")
    }
    
    func toolExecutionDidUpdateMessage(at index: Int, with message: ChatMessage) {
        if index < messages.count {
            // Update with cleaned content from tool coordinator
            messages[index] = MessageFactory.updated(
                messages[index],
                content: message.content.isEmpty ? messages[index].content : message.content,
                reasoning: message.reasoning,
                state: message.state
            )
        }
    }
}

// MARK: - ResponseOrchestrationDelegate

extension ConversationManager: ResponseOrchestrationDelegate {
    func orchestrationDidUpdateState(_ state: ConversationState) {
        updateState(state)
    }
    
    func orchestrationNeedsAPIHistory() -> [ChatMessage] {
        return apiHistory
    }
    
    func orchestrationDidCreateMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    func orchestrationDidUpdateMessage(at index: Int, with message: ChatMessage) {
        if index < messages.count {
            messages[index] = message
        }
    }
    
    func orchestrationNeedsMessage(at index: Int) -> ChatMessage? {
        return index < messages.count ? messages[index] : nil
    }
    
    func orchestrationNeedsMessageCount() -> Int {
        return messages.count
    }
    
    func orchestrationNeedsMeaningfulResponse(from history: [ChatMessage]) -> String {
        return generateMeaningfulResponseContent(from: history)
    }
}