import Foundation
import SwiftUI
import UIKit
import Combine

/// Manages conversation flow, message handling, and coordination between streaming, tools, and persistence
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published Properties
    
    // Full conversation history (used for API context and persistence)
    @Published private(set) var allMessages: [ChatMessage] = []
    
    // Windowed messages for UI display (performance optimization)
    @Published private(set) var displayMessages: [ChatMessage] = []
    
    // Indicates if there are more messages to load
    @Published private(set) var canLoadMore: Bool = false
    
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
    
    // Message windowing configuration
    private let initialWindowSize: Int = 50
    private let loadMoreBatchSize: Int = 25
    private var displayOffset: Int = 0  // Tracks how many older messages we've loaded
    
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
        allMessages.filter { message in
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
        self.retryManager = MessageRetryManager(networkMonitor: networkMonitor)
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
        
        allMessages.append(userMessage)
        updateDisplayWindow()
        let messageIndex = allMessages.count - 1
        await persistMessages()
        
        // Check if offline before attempting
        guard networkMonitor.isConnected else {
            updateMessageSendStatus(at: messageIndex, status: .offline)
            retryManager.addToOfflineQueue(allMessages[messageIndex].id)
            self.offlineQueueCount = self.retryManager.offlineQueue.count
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
                updateDisplayWindow()
                
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
                    retryManager.addToOfflineQueue(allMessages[messageIndex].id)
                    self.offlineQueueCount = self.retryManager.offlineQueue.count
                    await persistMessages()
                    throw SendError.offline
                }
                
                // If not retryable or last attempt, fail
                if !canRetry || attempt >= maxAttempts {
                    // Allow manual retry even if auto-retry exhausted or not applicable
                    let allowManualRetry = (!canRetry) || attempt >= maxAttempts
                    updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: allowManualRetry))
                    updateDisplayWindow()
                    await persistMessages()
                    updateState(.error(error.localizedDescription))
                    throw error
                }
                
                // Update status to retrying (show next attempt number)
                updateMessageSendStatus(at: messageIndex, status: .retrying(attempt: attempt + 1, maxAttempts: maxAttempts))
                updateDisplayWindow()
                await persistMessages()
                
                // Calculate delay with exponential backoff and constant jitter
                let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
                let jitter = Double.random(in: 0...0.1)  // 0-100ms constant jitter
                let delay = min(exponentialDelay + jitter, maxDelay)
                
                print("🔄 Retrying message (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.1f", delay))s delay...")
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Should never reach here - loop always throws on last attempt
        throw SendError.cannotRetry
    }
    
    /// Manually retry a failed message
    func retryFailedMessage(at index: Int) async throws {
        guard index < allMessages.count else { return }
        
        let message = allMessages[index]
        guard message.role == .user,
              let status = message.sendStatus,
              status.canRetry else {
            throw SendError.cannotRetry
        }
        
        // Retry the existing message in-place
        try await retryExistingMessage(at: index)
    }
    
    /// Retry an existing message at a specific index (in-place, no new message)
    private func retryExistingMessage(at messageIndex: Int) async throws {
        guard config.hasValidApiKey else {
            throw ConfigurationError.missingApiKey
        }
        
        // Check if offline before attempting
        guard networkMonitor.isConnected else {
            updateMessageSendStatus(at: messageIndex, status: .offline)
            retryManager.addToOfflineQueue(allMessages[messageIndex].id)
            self.offlineQueueCount = self.retryManager.offlineQueue.count
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
                updateDisplayWindow()
                
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
                    retryManager.addToOfflineQueue(allMessages[messageIndex].id)
                    self.offlineQueueCount = self.retryManager.offlineQueue.count
                    await persistMessages()
                    throw SendError.offline
                }
                
                // If not retryable or last attempt, fail
                if !canRetry || attempt >= maxAttempts {
                    // Allow manual retry even if auto-retry exhausted or not applicable
                    let allowManualRetry = (!canRetry) || attempt >= maxAttempts
                    updateMessageSendStatus(at: messageIndex, status: .failed(reason: failureReason, canRetry: allowManualRetry))
                    updateDisplayWindow()
                    await persistMessages()
                    updateState(.error(error.localizedDescription))
                    throw error
                }
                
                // Update status to retrying (show next attempt number)
                updateMessageSendStatus(at: messageIndex, status: .retrying(attempt: attempt + 1, maxAttempts: maxAttempts))
                updateDisplayWindow()
                await persistMessages()
                
                // Calculate delay with exponential backoff and constant jitter
                let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
                let jitter = Double.random(in: 0...0.1)  // 0-100ms constant jitter
                let delay = min(exponentialDelay + jitter, maxDelay)
                
                print("🔄 Retrying message (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.1f", delay))s delay...")
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Should never reach here, but handle gracefully
        throw SendError.cannotRetry
    }
    
    /// Load conversation from persistence
    func loadConversation() async {
        do {
            allMessages = try persistence.load()
            updateDisplayWindow()
        } catch {
            logger.logError(error, context: "loadConversation")
            allMessages = []
            displayMessages = []
            canLoadMore = false
        }
    }
    
    /// Clear all messages and persistence
    func clearConversation() async {
        allMessages.removeAll()
        displayMessages.removeAll()
        canLoadMore = false
        displayOffset = 0
        do {
            try persistence.clear()
        } catch {
            logger.logError(error, context: "clearConversation")
        }
    }
    
    /// Load more older messages into the display window
    func loadMoreMessages() {
        let totalMessages = allMessages.count
        let currentDisplayCount = displayMessages.count
        
        // Calculate how many more messages we can load
        let availableOlderMessages = totalMessages - currentDisplayCount
        guard availableOlderMessages > 0 else {
            canLoadMore = false
            return
        }
        
        // Increase offset by batch size
        displayOffset += loadMoreBatchSize
        updateDisplayWindow()
        
        logger.log(.info, "Loaded \(loadMoreBatchSize) more messages. Display: \(displayMessages.count)/\(totalMessages)", context: "loadMoreMessages")
    }
    
    // MARK: - Send Status Management
    
    /// Update send status for a message
    private func updateMessageSendStatus(at index: Int, status: SendStatus) {
        guard index < allMessages.count else { return }
        allMessages[index] = allMessages[index].withSendStatus(status)
    }
    
    /// Update the display window based on current offset and window size
    private func updateDisplayWindow() {
        let totalMessages = allMessages.count
        
        // If we have fewer messages than initial window, show all
        if totalMessages <= initialWindowSize {
            displayMessages = allMessages
            canLoadMore = false
            displayOffset = 0
            return
        }
        
        // Calculate window size (initial + loaded batches)
        let windowSize = initialWindowSize + displayOffset
        
        // Determine start index (show most recent messages)
        let startIndex = max(0, totalMessages - windowSize)
        displayMessages = Array(allMessages[startIndex..<totalMessages])
        
        // Can load more if we're not showing everything
        canLoadMore = startIndex > 0
        
        logger.log(.debug, "Display window updated: showing \(displayMessages.count)/\(totalMessages) messages, canLoadMore: \(canLoadMore)", context: "updateDisplayWindow")
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
            case .networkError(_, _):
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
                    // Clear the queue and get queued message IDs
                    let queuedMessageIds = self.retryManager.clearOfflineQueue()
                    print("🌐 ConversationManager: Processing \(queuedMessageIds.count) queued messages")
                    
                    self.offlineQueueCount = 0
                    
                    // Actually retry each queued message
                    Task {
                        for messageId in queuedMessageIds {
                            // Find the message index
                            if let index = self.allMessages.firstIndex(where: { $0.id == messageId }) {
                                print("🔄 ConversationManager: Retrying message at index \(index)")
                                try? await self.retryFailedMessage(at: index)
                            }
                        }
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
            try persistence.save(allMessages)
            logger.logPersistence("save", messageCount: allMessages.count)
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
        allMessages.append(message)
        updateDisplayWindow()
        let index = allMessages.count - 1
        logger.log(ConversationLogger.LogLevel.debug, "Streaming message created at index \(index)", context: "Streaming")
        return index
    }
    
    func streamingDidUpdateMessage(at index: Int, with message: ChatMessage) {
        // Update our messages array with the latest version
        if index < allMessages.count {
            allMessages[index] = message
            updateDisplayWindow()
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
        if index < allMessages.count {
            // Update with cleaned content from tool coordinator
            allMessages[index] = MessageFactory.updated(
                allMessages[index],
                content: message.content.isEmpty ? allMessages[index].content : message.content,
                reasoning: message.reasoning,
                state: message.state
            )
            updateDisplayWindow()
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
        allMessages.append(message)
        updateDisplayWindow()
    }
    
    func orchestrationDidUpdateMessage(at index: Int, with message: ChatMessage) {
        if index < allMessages.count {
            allMessages[index] = message
            updateDisplayWindow()
        }
    }
    
    func orchestrationNeedsMessage(at index: Int) -> ChatMessage? {
        return index < allMessages.count ? allMessages[index] : nil
    }
    
    func orchestrationNeedsMessageCount() -> Int {
        return allMessages.count
    }
    
    func orchestrationNeedsMeaningfulResponse(from history: [ChatMessage]) -> String {
        return generateMeaningfulResponseContent(from: history)
    }
}