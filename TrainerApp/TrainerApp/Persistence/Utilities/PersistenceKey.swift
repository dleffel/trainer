import Foundation

// MARK: - Central Key Registry

/// Central registry for all persistence keys across the application
/// This prevents key collisions and provides a single source of truth
enum PersistenceKey {
    
    // MARK: - Settings (Tier 1: UserDefaults)
    
    enum Settings {
        static let apiKey = "OPENROUTER_API_KEY"
        static let developerMode = "DeveloperModeEnabled"
        static let apiLogging = "APILoggingEnabled"
        static let dateProviderTestMode = "DateProvider_TestMode"
        static let dateProviderSimulatedDate = "DateProvider_SimulatedDate"
        static let dateProviderTimeOffset = "DateProvider_TimeOffset"
    }
    
    // MARK: - Training Data (Tier 2: Hybrid Storage)
    
    enum Training {
        /// Key for the training program object
        static let program = "TrainingProgram"
        
        /// Prefix for workout day keys (append date: workout_yyyy-MM-dd)
        static let workoutPrefix = "workout_"
        
        /// Prefix for workout results keys (append date: workout_results_yyyy-MM-dd)
        static let resultsPrefix = "workout_results_"
        
        /// Generate a workout key for a specific date
        static func workoutKey(for date: Date) -> String {
            return "\(workoutPrefix)\(dateKey(for: date))"
        }
        
        /// Generate a results key for a specific date
        static func resultsKey(for date: Date) -> String {
            return "\(resultsPrefix)\(dateKey(for: date))"
        }
    }
    
    // MARK: - Conversations (Tier 2/3: Hybrid/File)
    
    enum Conversation {
        /// Key for conversation messages in iCloud KV store
        static let messages = "trainer_conversations"
        
        /// Local file name for conversation backup
        static let localFileName = "conversation.json"
    }
    
    // MARK: - Message Retry (Tier 2: Hybrid Storage)
    
    enum MessageRetry {
        /// Prefix for message retry status keys (append messageId)
        static let statusPrefix = "message_retry_status_"
        
        /// Key for offline queue
        static let offlineQueue = "message_retry_offline_queue"
        
        /// Generate a retry status key for a specific message
        static func status(_ messageId: UUID) -> String {
            return "\(statusPrefix)\(messageId.uuidString)"
        }
    }
    
    // MARK: - Logging (Tier 3: File-Based)
    
    enum Logging {
        /// Directory name for API logs
        static let apiLogsDirectory = "APILogs"
        
        /// Active log file name
        static let activeLogFile = "api_logs.json"
        
        /// Metadata file name
        static let metadataFile = "api_logs_metadata.json"
    }
    
    // MARK: - Helper Methods
    
    /// Generate a standardized date key (yyyy-MM-dd in UTC)
    /// This MUST be used for all date-based keys to ensure consistency
    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}