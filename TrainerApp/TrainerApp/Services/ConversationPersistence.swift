import Foundation
import CloudKit

// MARK: - Chat Message Types

/// Represents the current state of a message
enum MessageState: String, Codable {
    case completed    // Message is final, never changes
    case streaming    // Message is being updated via streaming
    case processing   // Message completed but tools are running
}

/// Represents an attachment to a message (e.g., image, video)
struct MessageAttachment: Codable, Identifiable {
    let id: UUID
    let type: AttachmentType
    let data: Data  // Image data (JPEG compressed)
    let mimeType: String  // e.g., "image/jpeg"
    
    enum AttachmentType: String, Codable {
        case image
        // Future: video, document, etc.
    }
    
    init(id: UUID = UUID(), type: AttachmentType, data: Data, mimeType: String = "image/jpeg") {
        self.id = id
        self.type = type
        self.data = data
        self.mimeType = mimeType
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let reasoning: String?
    let date: Date
    var state: MessageState
    let attachments: [MessageAttachment]?  // Optional array of attachments
    
    // NEW: Send status tracking (only relevant for user messages)
    var sendStatus: SendStatus?
    var lastRetryAttempt: Date?
    var retryCount: Int
    
    init(id: UUID = UUID(), role: Role, content: String, reasoning: String? = nil, date: Date = Date.current, state: MessageState = .completed, attachments: [MessageAttachment]? = nil, sendStatus: SendStatus? = nil, lastRetryAttempt: Date? = nil, retryCount: Int = 0) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.date = date
        self.state = state
        self.attachments = attachments
        self.sendStatus = sendStatus
        self.lastRetryAttempt = lastRetryAttempt
        self.retryCount = retryCount
    }
    
    /// Create a mutable copy of this message with new content (only if currently streaming)
    func updatedContent(_ newContent: String, reasoning: String? = nil) -> ChatMessage? {
        guard state == .streaming else { return nil }
        return ChatMessage(id: id, role: role, content: newContent, reasoning: reasoning ?? self.reasoning, date: date, state: state, attachments: attachments, sendStatus: sendStatus, lastRetryAttempt: lastRetryAttempt, retryCount: retryCount)
    }
    
    /// Mark message as completed (no longer modifiable)
    func markCompleted() -> ChatMessage {
        return ChatMessage(id: id, role: role, content: content, reasoning: reasoning, date: date, state: .completed, attachments: attachments, sendStatus: sendStatus, lastRetryAttempt: lastRetryAttempt, retryCount: retryCount)
    }
    
    /// Update send status
    func withSendStatus(_ newStatus: SendStatus) -> ChatMessage {
        // Only increment retry count when transitioning to .retrying, not .sending
        let shouldIncrementRetry: Bool
        switch newStatus {
        case .retrying:
            shouldIncrementRetry = true
        default:
            shouldIncrementRetry = false
        }
        
        return ChatMessage(id: id, role: role, content: content, reasoning: reasoning, date: date, state: state, attachments: attachments, sendStatus: newStatus, lastRetryAttempt: Date.current, retryCount: retryCount + (shouldIncrementRetry ? 1 : 0))
    }

    enum Role: String, Codable {
        case user, assistant, system
    }
}

// MARK: - Storage Message Type

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let reasoning: String?  // Optional for reasoning models
    let date: Date
    let state: String?  // Optional for backwards compatibility
    let attachments: [MessageAttachment]?  // Optional for image attachments
    let sendStatus: SendStatus?  // Optional for send tracking
    let lastRetryAttempt: Date?
    let retryCount: Int?
    
    init(id: UUID, role: String, content: String, reasoning: String? = nil, date: Date, state: String? = nil, attachments: [MessageAttachment]? = nil, sendStatus: SendStatus? = nil, lastRetryAttempt: Date? = nil, retryCount: Int? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.date = date
        self.state = state
        self.attachments = attachments
        self.sendStatus = sendStatus
        self.lastRetryAttempt = lastRetryAttempt
        self.retryCount = retryCount
    }
}

// MARK: - Conversation Persistence

struct ConversationPersistence {
    // Use HybridCloudStore for conversations (with 1MB limit awareness)
    private let cloudStore: HybridCloudStore<[StoredMessage]>
    
    // Use FileStore as backup for large conversations
    private let fileStore: FileStore<[StoredMessage]>
    
    init() {
        // Initialize hybrid cloud store for synced conversations
        self.cloudStore = HybridCloudStore<[StoredMessage]>()
        
        // Initialize file store for large conversation fallback
        do {
            self.fileStore = try FileStore<[StoredMessage]>(subdirectory: "Conversations")
        } catch {
            fatalError("Failed to initialize FileStore: \(error)")
        }
        
        print("✅ ConversationPersistence initialized with HybridCloudStore + FileStore fallback")
    }
    
    // MARK: - Public API
    
    func load() throws -> [ChatMessage] {
        // Try cloud store first (for recent, small conversations)
        if let stored = cloudStore.load(forKey: PersistenceKey.Conversation.messages) {
            print("✅ Loaded \(stored.count) messages from iCloud")
            return convertToMessages(stored)
        }
        
        // Fallback to file store (for larger conversations)
        if let stored = fileStore.load(forKey: PersistenceKey.Conversation.localFileName) {
            print("📱 Loaded \(stored.count) messages from local file storage")
            return convertToMessages(stored)
        }
        
        print("📭 No conversation history found")
        return []
    }
    
    func save(_ messages: [ChatMessage]) throws {
        let stored = convertToStored(messages)
        
        // Estimate size
        let data = try JSONEncoder().encode(stored)
        let sizeInBytes = data.count
        
        // Use cloud store if under 1MB limit, otherwise use file store
        if sizeInBytes < 1_000_000 {
            do {
                try cloudStore.save(stored, forKey: PersistenceKey.Conversation.messages)
                print("☁️ Saved \(messages.count) messages to iCloud (\(sizeInBytes) bytes)")
                
                // Clean up file store if we successfully saved to cloud
                try? fileStore.delete(forKey: PersistenceKey.Conversation.localFileName)
            } catch {
                // Fallback to file store if cloud save fails
                print("⚠️ Cloud save failed, falling back to file storage: \(error)")
                try fileStore.save(stored, forKey: PersistenceKey.Conversation.localFileName)
            }
        } else {
            // Conversation too large for iCloud KV store, use file storage
            try fileStore.save(stored, forKey: PersistenceKey.Conversation.localFileName)
            print("📱 Saved \(messages.count) messages to local file storage (\(sizeInBytes) bytes - too large for iCloud)")
            
            // Clean up cloud store since we've moved to files
            try? cloudStore.delete(forKey: PersistenceKey.Conversation.messages)
        }
    }
    
    func clear() throws {
        // Clear from both stores
        try? cloudStore.delete(forKey: PersistenceKey.Conversation.messages)
        try? fileStore.delete(forKey: PersistenceKey.Conversation.localFileName)
        print("🧹 Cleared all conversation history")
    }
    
    // MARK: - Conversion Helpers
    
    private func convertToMessages(_ stored: [StoredMessage]) -> [ChatMessage] {
        return stored.compactMap { s in
            guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
            let state = MessageState(rawValue: s.state ?? "completed") ?? .completed
            return ChatMessage(id: s.id, role: role, content: s.content, reasoning: s.reasoning, date: s.date, state: state, attachments: s.attachments, sendStatus: s.sendStatus, lastRetryAttempt: s.lastRetryAttempt, retryCount: s.retryCount ?? 0)
        }
    }
    
    private func convertToStored(_ messages: [ChatMessage]) -> [StoredMessage] {
        return messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, reasoning: m.reasoning, date: m.date, state: m.state.rawValue, attachments: m.attachments, sendStatus: m.sendStatus, lastRetryAttempt: m.lastRetryAttempt, retryCount: m.retryCount)
        }
    }
}