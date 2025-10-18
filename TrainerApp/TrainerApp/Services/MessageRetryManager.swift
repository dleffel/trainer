import Foundation
import SwiftUI

/// Manages message retry logic with exponential backoff and offline queue
@MainActor
class MessageRetryManager: ObservableObject {
    
    // MARK: - Configuration
    
    struct RetryConfiguration {
        let maxAttempts: Int = 3
        let baseDelay: TimeInterval = 1.0  // 1 second
        let maxDelay: TimeInterval = 30.0  // 30 seconds
        let backoffMultiplier: Double = 2.0
        let retryableErrors: Set<SendStatus.FailureReason> = [
            .networkError,
            .timeout,
            .serverError,
            .rateLimitError
        ]
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var sendStatus: [UUID: SendStatus] = [:]
    @Published private(set) var offlineQueue: [UUID] = []
    @Published private(set) var activeRetries: Set<UUID> = []
    
    // MARK: - Private Properties
    
    private let config = RetryConfiguration()
    private let networkMonitor: NetworkMonitor
    private let persistence: HybridCloudStore<RetryState>
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Dependencies
    
    private let llmService: LLMServiceProtocol
    
    // MARK: - Initialization
    
    init(
        networkMonitor: NetworkMonitor = .shared,
        llmService: LLMServiceProtocol = LLMService.shared
    ) {
        self.networkMonitor = networkMonitor
        self.llmService = llmService
        self.persistence = HybridCloudStore<RetryState>()
        
        // Load persisted retry state
        loadPersistedState()
        
        // Observe network changes
        setupNetworkObserver()
    }
    
    // MARK: - Public Interface
    
    /// Send a message with automatic retry on failure
    func sendMessage(
        _ message: ChatMessage,
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void = { _ in },
        onReasoning: @escaping (String) -> Void = { _ in }
    ) async throws -> (content: String, reasoning: String?) {
        
        // Check network status
        guard networkMonitor.isConnected else {
            // Add to offline queue
            addToOfflineQueue(message.id)
            updateSendStatus(message.id, status: .offline)
            throw SendError.offline
        }
        
        return try await sendWithRetry(
            messageId: message.id,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            onToken: onToken,
            onReasoning: onReasoning,
            attempt: 1
        )
    }
    
    /// Manually retry a failed message
    func retryMessage(_ messageId: UUID) async throws {
        guard let status = sendStatus[messageId], status.canRetry else {
            throw SendError.cannotRetry
        }
        
        // Remove from offline queue if present
        offlineQueue.removeAll { $0 == messageId }
        
        // Note: Actual retry logic would need message context
        // This is a placeholder - the real implementation would be called from ConversationManager
        print("🔄 MessageRetryManager: Manual retry requested for message \(messageId)")
    }
    
    /// Cancel an ongoing retry
    func cancelRetry(_ messageId: UUID) {
        retryTasks[messageId]?.cancel()
        retryTasks.removeValue(forKey: messageId)
        activeRetries.remove(messageId)
        updateSendStatus(messageId, status: .failed(reason: .unknown, canRetry: true))
    }
    
    /// Get send status for a message
    func getSendStatus(_ messageId: UUID) -> SendStatus {
        return sendStatus[messageId] ?? .notSent
    }
    
    /// Process offline queue when network returns
    func processOfflineQueue() async {
        guard networkMonitor.isConnected else { return }
        
        let queuedMessages = offlineQueue
        offlineQueue.removeAll()
        
        print("🔄 MessageRetryManager: Processing \(queuedMessages.count) offline messages")
        
        // Note: Processing would be coordinated with ConversationManager
        // This is a notification mechanism
        for messageId in queuedMessages {
            updateSendStatus(messageId, status: .notSent)
        }
    }
    
    // MARK: - Private Methods
    
    /// Send with exponential backoff retry
    private func sendWithRetry(
        messageId: UUID,
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void,
        attempt: Int
    ) async throws -> (content: String, reasoning: String?) {
        
        // Update status
        if attempt == 1 {
            updateSendStatus(messageId, status: .sending)
        } else {
            updateSendStatus(messageId, status: .retrying(attempt: attempt, maxAttempts: config.maxAttempts))
        }
        
        do {
            // Attempt to send via streaming
            let result = try await llmService.streamComplete(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                history: history,
                onToken: onToken,
                onReasoning: onReasoning
            )
            
            // Success!
            updateSendStatus(messageId, status: .sent)
            clearRetryState(messageId)
            return result
            
        } catch {
            // Check if we should retry
            let failureReason = classifyError(error)
            let canRetry = config.retryableErrors.contains(failureReason) && attempt < config.maxAttempts
            
            if canRetry {
                // Calculate delay with exponential backoff
                let delay = calculateDelay(attempt: attempt)
                print("🔄 MessageRetryManager: Retry attempt \(attempt + 1)/\(config.maxAttempts) after \(delay)s delay")
                
                // Save retry state
                saveRetryState(messageId, attempt: attempt, error: error.localizedDescription)
                
                // Wait before retry
                try? await Task.sleep(for: .seconds(delay))
                
                // Check if cancelled
                try Task.checkCancellation()
                
                // Retry
                return try await sendWithRetry(
                    messageId: messageId,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    history: history,
                    onToken: onToken,
                    onReasoning: onReasoning,
                    attempt: attempt + 1
                )
            } else {
                // Failed permanently or non-retryable
                updateSendStatus(messageId, status: .failed(reason: failureReason, canRetry: false))
                saveRetryState(messageId, attempt: attempt, error: error.localizedDescription)
                throw error
            }
        }
    }
    
    /// Calculate exponential backoff delay with jitter
    private func calculateDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = config.baseDelay * pow(config.backoffMultiplier, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.1) * exponentialDelay  // 0-10% jitter
        return min(exponentialDelay + jitter, config.maxDelay)
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
    
    /// Update send status and notify observers
    private func updateSendStatus(_ messageId: UUID, status: SendStatus) {
        sendStatus[messageId] = status
        
        if status.isActive {
            activeRetries.insert(messageId)
        } else {
            activeRetries.remove(messageId)
        }
    }
    
    /// Add message to offline queue
    private func addToOfflineQueue(_ messageId: UUID) {
        if !offlineQueue.contains(messageId) {
            offlineQueue.append(messageId)
            saveOfflineQueue()
        }
    }
    
    /// Setup network observer to process queue when online
    private func setupNetworkObserver() {
        // Observe network status changes
        Task {
            for await _ in NotificationCenter.default.notifications(named: NSNotification.Name("NetworkStatusChanged")) {
                if networkMonitor.isConnected {
                    await processOfflineQueue()
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveRetryState(_ messageId: UUID, attempt: Int, error: String) {
        let state = RetryState(
            messageId: messageId,
            attempt: attempt,
            lastAttemptDate: Date.current,
            error: error,
            status: sendStatus[messageId] ?? .notSent
        )
        
        do {
            try persistence.save(state, forKey: PersistenceKey.MessageRetry.status(messageId))
        } catch {
            print("⚠️ MessageRetryManager: Failed to save retry state: \(error)")
        }
    }
    
    private func clearRetryState(_ messageId: UUID) {
        do {
            try persistence.delete(forKey: PersistenceKey.MessageRetry.status(messageId))
        } catch {
            print("⚠️ MessageRetryManager: Failed to clear retry state: \(error)")
        }
        
        sendStatus.removeValue(forKey: messageId)
    }
    
    private func loadPersistedState() {
        // Load offline queue (stored as array of UUIDs)
        // Note: Using SimpleKeyValueStore would be more appropriate for this
        // For now, skip persistence of offline queue since HybridCloudStore expects RetryState
        print("📦 MessageRetryManager: Initialized (offline queue persistence not yet implemented)")
    }
    
    private func saveOfflineQueue() {
        // Skip for now - would need SimpleKeyValueStore or different persistence strategy
        print("📦 MessageRetryManager: Offline queue saved (persistence not yet implemented)")
    }
}

// MARK: - Supporting Types

/// Persisted retry state
struct RetryState: Codable {
    let messageId: UUID
    let attempt: Int
    let lastAttemptDate: Date
    let error: String?
    let status: SendStatus
}

/// Send-specific errors
enum SendError: LocalizedError {
    case offline
    case cannotRetry
    case maxAttemptsReached
    
    var errorDescription: String? {
        switch self {
        case .offline:
            return "No network connection"
        case .cannotRetry:
            return "Message cannot be retried"
        case .maxAttemptsReached:
            return "Maximum retry attempts reached"
        }
    }
}
