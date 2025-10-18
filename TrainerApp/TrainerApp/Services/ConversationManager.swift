import Foundation
import SwiftUI
import UIKit
import Combine

/// Manages conversation flow, message handling, and coordination between streaming, tools, and persistence
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var conversationState: ConversationState = .idle
    
    // Reasoning preview state for UI
    @Published private(set) var isStreamingReasoning: Bool = false
    @Published private(set) var latestReasoningChunk: String? = nil
    
    // Network status for UI
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var offlineQueueCount: Int = 0
    
    // MARK: - Private Properties
    private let persistence = ConversationPersistence()
    private let config: AppConfiguration
    private let logger = ConversationLogger.shared
    private var networkCancellable: AnyCancellable?
    
    // MARK: - Coordinators
    private let streamingCoordinator: StreamingCoordinator
    private let toolCoordinator: ToolExecutionCoordinator
    private let responseOrchestrator: ResponseOrchestrator
    private let retryManager: MessageRetryManager
    private let networkMonitor: NetworkMonitor
    
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
        llmService: LLMServiceProtocol = LLMService.shared,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.config = config
        self.networkMonitor = networkMonitor
        
        // Initialize coordinators
        self.streamingCoordinator = StreamingCoordinator(llmService: llmService)
        self.toolCoordinator = ToolExecutionCoordinator()
        self.retryManager = MessageRetryManager(networkMonitor: networkMonitor, llmService: llmService)
        self.responseOrchestrator = ResponseOrchestrator(
            streamingCoordinator: streamingCoordinator,
            toolCoordinator: toolCoordinator,
            llmService: llmService
        )
        
        // Set up delegates
        self.streamingCoordinator.delegate = self
        self.toolCoordinator.delegate = self
        self.responseOrchestrator.delegate = self
        
        // Observe network status
        setupNetworkObservation()
    }
    
    // MARK: - Public Interface
    
    /// Initialize and load existing conversation
    func initialize() async {
        await loadConversation()
        
        // Start network monitoring
        networkMonitor.startMonitoring()
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
        // Create and add user message using MessageFactory with .notSent status
        let userMessage = images.isEmpty
            ? MessageFactory.user(content: text, sendStatus: .notSent)
            : MessageFactory.userWithImages(content: text, images: images, sendStatus: .notSent)
        
        messages.append(userMessage)
        let messageIndex = messages.count - 1
        await persistMessages()
        
        // Check if offline before attempting
        guard networkMonitor.isConnected else {
            updateMessageSendStatus(at: messageIndex, status: .offline)
            retryManager.addToOfflineQueue(messages[messageIndex].id)
            await persistMessages()
            throw SendError.offline
        }
        
        // Update to sending status
        updateMessageSendStatus(at: messageIndex, status: .sending)
        
        // Start conversation flow via orchestrator with automatic retry
        updateState(.preparingResponse)
        
        // Retry configuration
        let maxAttempts = 3
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        let backoffMultiplier: Double = 2.0
        
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                // Attempt to send
                let result = try await responseOrchestrator.executeConversationFlow(
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt
                )
                
                logger.log(ConversationLogger.LogLevel.info, "Conversation completed in \(result.turns) turns, hadTools: \(result.hadTools)", context: "sendMessage")
                
                // Mark as sent
                updateMessageSendStatus(at: messageIndex, status: .sent)
                
                // Persist after successful completion
                await persistMessages()
                return // Success!
                
            } catch {
                lastError = error
                logger.logError(error, context: "sendMessage(attempt \(attempt)/\(maxAttempts))")
                
                // Check if error is retryable
                let failureReason = classifyError(error)
                let canRetry = shouldRetry(error: error)
                
                // Check if offline
                if !networkMonitor.isConnected {
                    updateMessageSendStatus(at: messageIndex, status: .offline)
                    retryManager.addToOfflineQueue(messages[messageIndex].id)
                    await persistMessages()
                    throw SendError.offline
                }
                
                // If not retryable or last attempt, fail
                if !canRetry || attempt >= maxAttempts {
                    updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: canRetry))
                    await persistMessages()
                    updateState(.error(error.localizedDescription))
                    throw error
                }
                
                // Update status to retrying
                updateMessageSendStatus(at: messageIndex, status: .retrying(attempt: attempt, maxAttempts: maxAttempts))
                await persistMessages()
                
                // Calculate delay with exponential backoff and jitter
                let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
                let jitter = Double.random(in: 0...0.1) * exponentialDelay
                let delay = min(exponentialDelay + jitter, maxDelay)
                
                print("🔄 Retrying message (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.1f", delay))s delay...")
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        if let error = lastError {
            let failureReason = classifyError(error)
            updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: false))
            await persistMessages()
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    /// Manually retry a failed message
    func retryFailedMessage(at index: Int) async throws {
        guard index < messages.count else { return }
        
        let message = messages[index]
        guard message.role == .user,
              let status = message.sendStatus,
              status.canRetry else {
            throw SendError.cannotRetry
        }
        
        // Extract images if any
        let images = extractImages(from: message)
        
        // Retry the existing message in-place
        try await retryExistingMessage(at: index, text: message.content, images: images)
    }
    
    /// Retry an existing message at a specific index (in-place, no new message)
    private func retryExistingMessage(at messageIndex: Int, text: String, images: [UIImage]) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        // Check if offline before attempting
        guard networkMonitor.isConnected else {
            updateMessageSendStatus(at: messageIndex, status: .offline)
            retryManager.addToOfflineQueue(messages[messageIndex].id)
            await persistMessages()
            throw SendError.offline
        }
        
        // Update to sending status
        updateMessageSendStatus(at: messageIndex, status: .sending)
        
        // Start conversation flow via orchestrator with automatic retry
        updateState(.preparingResponse)
        
        // Retry configuration
        let maxAttempts = 3
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        let backoffMultiplier: Double = 2.0
        
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                // Attempt to send
                let result = try await responseOrchestrator.executeConversationFlow(
                    apiKey: config.apiKey,
                    model: config.model,
                    systemPrompt: config.systemPrompt
                )
                
                logger.log(ConversationLogger.LogLevel.info, "Retry successful: \(result.turns) turns, hadTools: \(result.hadTools)", context: "retryExistingMessage")
                
                // Mark as sent
                updateMessageSendStatus(at: messageIndex, status: .sent)
                
                // Persist after successful completion
                await persistMessages()
                return // Success!
                
            } catch {
                lastError = error
                logger.logError(error, context: "retryExistingMessage(attempt \(attempt)/\(maxAttempts))")
                
                // Check if error is retryable
                let failureReason = classifyError(error)
                let canRetry = shouldRetry(error: error)
                
                // Check if offline
                if !networkMonitor.isConnected {
                    updateMessageSendStatus(at: messageIndex, status: .offline)
                    retryManager.addToOfflineQueue(messages[messageIndex].id)
                    await persistMessages()
                    throw SendError.offline
                }
                
                // If not retryable or last attempt, fail
                if !canRetry || attempt >= maxAttempts {
                    updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: canRetry))
                    await persistMessages()
                    updateState(.error(error.localizedDescription))
                    throw error
                }
                
                // Update status to retrying
                updateMessageSendStatus(at: messageIndex, status: .retrying(attempt: attempt, maxAttempts: maxAttempts))
                await persistMessages()
                
                // Calculate delay with exponential backoff and jitter
                let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
                let jitter = Double.random(in: 0...0.1) * exponentialDelay
                let delay = min(exponentialDelay + jitter, maxDelay)
                
                print("🔄 Retrying message (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.1f", delay))s delay...")
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        if let error = lastError {
            let failureReason = classifyError(error)
            updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: false))
            await persistMessages()
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
    
    // MARK: - Send Status Management
    
    /// Update send status for a message
    private func updateMessageSendStatus(at index: Int, status: SendStatus) {
        guard index < messages.count else { return }
        messages[index] = messages[index].withSendStatus(status)
    }
    
    /// Classify error into failure reason
    private func classifyError(_ error: Error) -> SendStatus.FailureReason {
        if let llmError = error as? LLMError {
            switch llmError {
            case .httpError(let code, _):
                if code == 401 || code == 403 {
                    return .authenticationError
                } else if code == 429 {
                    return .rateLimitError
                } else if (500...599).contains(code) {
                    return .serverError
                } else {
                    return .unknown
                }
            case .timeout:
                return .timeout
            case .networkError:
                return .networkError
            default:
                return .unknown
            }
        }
        
        // Check for network errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost:
                return .networkError
            case NSURLErrorTimedOut:
                return .timeout
            default:
                return .networkError
            }
        }
        
        return .unknown
    }
    
    /// Determine if error is retryable
    private func shouldRetry(error: Error) -> Bool {
        if let llmError = error as? LLMError {
            return llmError.isRetryable
        }
        return true // Default to retryable for unknown errors
    }
    
    /// Extract images from message attachments
    private func extractImages(from message: ChatMessage) -> [UIImage] {
        guard let attachments = message.attachments else { return [] }
        return attachments.compactMap { attachment in
            guard attachment.type == .image else { return nil }
            return UIImage(data: attachment.data)
        }
    }
    
    /// Setup network observation using Combine
    private func setupNetworkObservation() {
        // Initial status
        isOnline = networkMonitor.isConnected
        offlineQueueCount = retryManager.offlineQueue.count
        
        // Observe network status changes using Combine
        networkCancellable = networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                
                let wasOffline = !self.isOnline
                self.isOnline = isConnected
                self.offlineQueueCount = self.retryManager.offlineQueue.count
                
                print("🌐 ConversationManager: Network status changed to \(isConnected ? "online" : "offline")")
                
                // Process offline queue when network returns
                if isConnected && wasOffline && !self.retryManager.offlineQueue.isEmpty {
                    print("🌐 ConversationManager: Processing \(self.retryManager.offlineQueue.count) queued messages")
                    Task {
                        await self.retryManager.processOfflineQueue()
                    }
                }
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
        updateState(.processingTool(name: toolName, description: description))
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