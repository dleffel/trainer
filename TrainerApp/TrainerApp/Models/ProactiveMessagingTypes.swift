import Foundation

// MARK: - Shared Types for Proactive Messaging

/// Context information gathered for coach decision-making
struct CoachContext {
    let currentTime: Date
    let dayOfWeek: String
    let lastMessageTime: Date?
    let todaysWorkout: String?
    let workoutCompleted: Bool
    let lastWorkoutTime: Date?
    let currentBlock: String
    let weekNumber: Int
    let recentMetrics: HealthMetrics?
    
    // Setup-related fields
    let programExists: Bool
    let hasHealthData: Bool
    let messagesSentToday: Int
    let daysSinceLastMessage: Int?
    
    /// Formatted prompt for LLM context
    var contextPrompt: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let currentTimeStr = timeFormatter.string(from: currentTime)
        
        var prompt = """
        CURRENT CONTEXT:
        - Time: \(currentTimeStr) on \(dayOfWeek)
        """
        
        if programExists {
            prompt += """
            
            - Training: Week \(weekNumber) of \(currentBlock) block
            - Today's workout: \(todaysWorkout ?? "Rest day")
            - Workout completed: \(workoutCompleted ? "Yes" : "No")
            """
        } else {
            prompt += """
            
            - Training: No active training program
            - Status: New athlete, needs program initialization
            """
        }
        
        // Add last message timing
        if let lastMessage = lastMessageTime {
            let hoursSince = currentTime.timeIntervalSince(lastMessage) / 3600
            prompt += "\n- Last message sent: \(Int(hoursSince)) hours ago"
        } else {
            prompt += "\n- Last message sent: Never"
        }
        
        // Add workout history
        if let lastWorkout = lastWorkoutTime {
            let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout, to: currentTime).day ?? 0
            prompt += "\n- Last workout: \(daysSince) days ago"
        }
        
        // Add health data status
        prompt += "\n- Health data: \(hasHealthData ? "Available" : "Not available")"
        
        if let metrics = recentMetrics {
            if let weight = metrics.weight {
                prompt += "\n- Current weight: \(String(format: "%.1f", weight)) lbs"
            }
        }
        
        prompt += "\n\nBased on this context, check setup state if needed, then decide on messaging."
        
        return prompt
    }
}

/// Decision made by the coach brain
struct CoachDecision {
    let shouldSendMessage: Bool
    let message: String?
    let reasoning: String
}

/// Health metrics used in decision-making
struct HealthMetrics {
    let weight: Double?
    let bodyFat: Double?
    let sleep: Double?
}

/// Settings for proactive messaging behavior
struct ProactiveMessagingSettings {
    var enabled: Bool = true
    var checkFrequency: TimeInterval = 30 * 60 // 30 minutes
    var quietHoursStart: Int? = 22 // 10 PM
    var quietHoursEnd: Int? = 6 // 6 AM
    var maxMessagesPerDay: Int = 3
    var minimumMessageInterval: TimeInterval = 60 * 60 // 1 hour between messages
    var sundayReviewEnabled: Bool = true
    var sundayReviewTime: DateComponents = DateComponents(hour: 19, minute: 0) // 7 PM
}

// MARK: - ChatMessage Type (if not already defined elsewhere)

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let date: Date
    
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
    
    init(id: UUID = UUID(), role: Role, content: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
    }
}

// MARK: - LLM Client Interface (placeholder if not defined elsewhere)

struct LLMClient {
    static func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        // This would be implemented elsewhere
        // Placeholder for compilation
        fatalError("LLMClient.complete should be implemented elsewhere")
    }
}