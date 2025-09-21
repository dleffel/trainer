import Foundation
import CloudKit

// MARK: - Chat Message Types

/// Represents the current state of a message
enum MessageState: String, Codable {
    case completed    // Message is final, never changes
    case streaming    // Message is being updated via streaming
    case processing   // Message completed but tools are running
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let date: Date
    var state: MessageState
    
    init(id: UUID = UUID(), role: Role, content: String, date: Date = Date.current, state: MessageState = .completed) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
        self.state = state
    }
    
    /// Create a mutable copy of this message with new content (only if currently streaming)
    func updatedContent(_ newContent: String) -> ChatMessage? {
        guard state == .streaming else { return nil }
        return ChatMessage(id: id, role: role, content: newContent, date: date, state: state)
    }
    
    /// Mark message as completed (no longer modifiable)
    func markCompleted() -> ChatMessage {
        return ChatMessage(id: id, role: role, content: content, date: date, state: .completed)
    }

    enum Role: String, Codable {
        case user, assistant, system
    }
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
    let state: String?  // Optional for backwards compatibility
    
    init(id: UUID, role: String, content: String, date: Date, state: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
        self.state = state
    }
}

// MARK: - Conversation Persistence

struct ConversationPersistence {
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private let conversationKey = "trainer_conversations"
    
    // Local backup URL
    private var localURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("conversation.json")
    }
    
    init() {
        // Synchronize with iCloud to get latest data
        let synchronized = keyValueStore.synchronize()
        print("🔄 iCloud synchronize on init: \(synchronized)")
    }
    
    func load() throws -> [ChatMessage] {
        // Try iCloud first
        if let data = keyValueStore.data(forKey: conversationKey) {
            let messages = try JSONDecoder().decode([StoredMessage].self, from: data)
            print("✅ Loaded from iCloud")
            return messages.compactMap { s in
                guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
                let state = MessageState(rawValue: s.state ?? "completed") ?? .completed
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date, state: state)
            }
        }
        
        // Fallback to local
        if FileManager.default.fileExists(atPath: localURL.path) {
            let data = try Data(contentsOf: localURL)
            let stored = try JSONDecoder().decode([StoredMessage].self, from: data)
            print("📱 Loaded from local storage")
            return stored.compactMap { s in
                guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
                let state = MessageState(rawValue: s.state ?? "completed") ?? .completed
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date, state: state)
            }
        }
        
        return []
    }
    
    func save(_ messages: [ChatMessage]) throws {
        let stored = messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, date: m.date, state: m.state.rawValue)
        }
        let data = try JSONEncoder().encode(stored)
        
        // Save to both local and iCloud
        try data.write(to: localURL, options: [.atomic])
        
        // Save to iCloud (1MB limit)
        if data.count < 1_000_000 {
            keyValueStore.set(data, forKey: conversationKey)
            let synced = keyValueStore.synchronize()
            print("☁️ Saved to iCloud (\(data.count) bytes) - Sync started: \(synced)")
            
            // Verify the save
            if let savedData = keyValueStore.data(forKey: conversationKey) {
                print("✅ Verified: Data exists in iCloud store (\(savedData.count) bytes)")
            } else {
                print("⚠️ Warning: Data not found in iCloud store after save")
            }
        } else {
            print("⚠️ Data too large for iCloud key-value store (\(data.count) bytes)")
        }
    }
    
    func clear() throws {
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        keyValueStore.removeObject(forKey: conversationKey)
        keyValueStore.synchronize()
    }
}