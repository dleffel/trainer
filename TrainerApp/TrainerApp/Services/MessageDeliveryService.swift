import Foundation
import UserNotifications

/// Protocol for message delivery abstraction
protocol MessageDeliveryProtocol {
    func sendProactiveMessage(_ message: String) async throws
    func requestNotificationPermissions() async throws -> Bool
    func setupNotificationCategories() async
}

/// Handles all aspects of message delivery: notifications, persistence, and formatting
class MessageDeliveryService: NSObject, MessageDeliveryProtocol {
    
    // MARK: - Properties
    private let notificationCenter = UNUserNotificationCenter.current()
    private let persistence = ConversationPersistence()
    
    // MARK: - Initialization
    override init() {
        super.init()
        notificationCenter.delegate = self
    }
    
    // MARK: - Public Interface
    
    /// Send a proactive message via notification and add to conversation
    func sendProactiveMessage(_ message: String) async throws {
        // First, add the message to the chat conversation
        await addMessageToConversation(message)
        
        // Then send the notification
        let content = UNMutableNotificationContent()
        content.title = "Your Rowing Coach"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "COACH_MESSAGE"
        
        // Add metadata
        content.userInfo = [
            "type": "proactive_coach",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await notificationCenter.add(request)
            print("📬 MessageDelivery: Sent message: \(message)")
        } catch {
            print("❌ MessageDelivery: Failed to send notification: \(error)")
            throw MessageDeliveryError.notificationFailed(error)
        }
    }
    
    /// Request notification permissions
    func requestNotificationPermissions() async throws -> Bool {
        print("📱 MessageDelivery: Requesting notification permissions...")
        
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            
            print("📱 MessageDelivery: Permissions granted: \(granted)")
            return granted
        } catch {
            print("❌ MessageDelivery: Failed to request permissions: \(error)")
            throw MessageDeliveryError.permissionRequestFailed(error)
        }
    }
    
    /// Setup notification categories and actions
    func setupNotificationCategories() async {
        let openAppAction = UNNotificationAction(
            identifier: "OPEN_APP",
            title: "Open App",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "COACH_MESSAGE",
            actions: [openAppAction, dismissAction],
            intentIdentifiers: []
        )
        
        notificationCenter.setNotificationCategories([category])
        print("✅ MessageDelivery: Notification categories configured")
    }
    
    // MARK: - Private Methods
    
    private func addMessageToConversation(_ message: String) async {
        await MainActor.run {
            // Load existing messages
            var messages = (try? persistence.load()) ?? []
            
            // Add the proactive message from the assistant
            let assistantMessage = ChatMessage(role: .assistant, content: message)
            messages.append(assistantMessage)
            
            // Save the updated conversation
            try? persistence.save(messages)
            
            print("💬 MessageDelivery: Added message to conversation")
            
            // Post notification to update UI if it's open
            NotificationCenter.default.post(
                name: Notification.Name("ProactiveMessageAdded"),
                object: nil,
                userInfo: ["message": assistantMessage]
            )
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MessageDeliveryService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "OPEN_APP", UNNotificationDefaultActionIdentifier:
            // User tapped the notification - app will open
            print("📱 MessageDelivery: User tapped notification")
            // Notify the scheduler that app was opened
            NotificationCenter.default.post(
                name: Notification.Name("AppOpenedFromNotification"),
                object: nil
            )
        case "DISMISS":
            // User dismissed - no action needed
            print("🚫 MessageDelivery: User dismissed notification")
            break
        default:
            break
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

// MARK: - Errors

enum MessageDeliveryError: LocalizedError {
    case notificationFailed(Error)
    case permissionRequestFailed(Error)
    case persistenceFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .notificationFailed(let error):
            return "Failed to send notification: \(error.localizedDescription)"
        case .permissionRequestFailed(let error):
            return "Failed to request permissions: \(error.localizedDescription)"
        case .persistenceFailed(let error):
            return "Failed to persist message: \(error.localizedDescription)"
        }
    }
}

// MARK: - Conversation Persistence (Moved from ProactiveCoachManager)

private struct ConversationPersistence {
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
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
            }
        }
        
        // Fallback to local
        if FileManager.default.fileExists(atPath: localURL.path) {
            let data = try Data(contentsOf: localURL)
            let stored = try JSONDecoder().decode([StoredMessage].self, from: data)
            print("📱 Loaded from local storage")
            return stored.compactMap { s in
                guard let role = ChatMessage.Role(rawValue: s.role) else { return nil }
                return ChatMessage(id: s.id, role: role, content: s.content, date: s.date)
            }
        }
        
        return []
    }
    
    func save(_ messages: [ChatMessage]) throws {
        let stored = messages.map { m in
            StoredMessage(id: m.id, role: m.role.rawValue, content: m.content, date: m.date)
        }
        let data = try JSONEncoder().encode(stored)
        
        // Save to both local and iCloud
        try data.write(to: localURL, options: [.atomic])
        
        // Save to iCloud (1MB limit)
        if data.count < 1_000_000 {
            keyValueStore.set(data, forKey: conversationKey)
            let synced = keyValueStore.synchronize()
            print("☁️ Saved to iCloud (\(data.count) bytes) - Sync started: \(synced)")
        } else {
            print("⚠️ Data too large for iCloud key-value store (\(data.count) bytes)")
        }
    }
}

private struct StoredMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let date: Date
}

// MARK: - Mock Implementation for Testing

class MockMessageDeliveryService: MessageDeliveryProtocol {
    var sentMessages: [String] = []
    var permissionsGranted = true
    var setupCategoriesCalled = false
    
    func sendProactiveMessage(_ message: String) async throws {
        sentMessages.append(message)
    }
    
    func requestNotificationPermissions() async throws -> Bool {
        return permissionsGranted
    }
    
    func setupNotificationCategories() async {
        setupCategoriesCalled = true
    }
}