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
    
    @Published private(set) var offlineQueue: [UUID] = []
    
    // MARK: - Private Properties
    
    private let config = RetryConfiguration()
    private let networkMonitor: NetworkMonitor
    private let queuePersistence: SimpleKeyValueStore<[UUID]>
    
    // MARK: - Initialization
    
    init(networkMonitor: NetworkMonitor = .shared) {
        self.networkMonitor = networkMonitor
        self.queuePersistence = SimpleKeyValueStore()
        
        // Load persisted offline queue
        loadPersistedState()
    }
    
    // MARK: - Public Interface
    
    // Note: Retry logic is implemented directly in ConversationManager to ensure
    // proper integration with ResponseOrchestrator for tool execution and state handling.
    // MessageRetryManager provides queue management and status tracking only.
    
    // MARK: - Private Methods
    // Note: All retry logic is implemented in ConversationManager to ensure
    // proper integration with ResponseOrchestrator for tool execution.
    // MessageRetryManager provides only queue management and persistence.
    
    /// Add message to offline queue
    func addToOfflineQueue(_ messageId: UUID) {
        if !offlineQueue.contains(messageId) {
            offlineQueue.append(messageId)
            saveOfflineQueue()
        }
    }
    /// Remove message from offline queue
    func removeFromOfflineQueue(_ messageId: UUID) {
        offlineQueue.removeAll { $0 == messageId }
        saveOfflineQueue()
    }
    
    /// Clear all messages from offline queue and return the list
    func clearOfflineQueue() -> [UUID] {
        let queuedMessages = Array(offlineQueue)
        offlineQueue.removeAll()
        saveOfflineQueue()
        return queuedMessages
    }
    
    
    // Network observation is handled by ConversationManager
    // which triggers actual retry through retryFailedMessage()
    
    // MARK: - Persistence
    
    private func loadPersistedState() {
        // Load offline queue using SimpleKeyValueStore
        if let loadedQueue: [UUID] = queuePersistence.load(forKey: PersistenceKey.MessageRetry.offlineQueue) {
            offlineQueue = loadedQueue
            print("📦 MessageRetryManager: Loaded \(loadedQueue.count) queued messages from persistence")
        } else {
            print("📦 MessageRetryManager: No persisted offline queue found")
        }
    }
    
    private func saveOfflineQueue() {
        do {
            try queuePersistence.save(offlineQueue, forKey: PersistenceKey.MessageRetry.offlineQueue)
            print("📦 MessageRetryManager: Saved \(offlineQueue.count) queued messages")
        } catch {
            print("⚠️ MessageRetryManager: Failed to save offline queue: \(error)")
        }
    }
}

// MARK: - Supporting Types

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
