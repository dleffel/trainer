import Foundation
import os.log

/// Centralized logging for conversation management
///
/// Provides structured, filterable logging for debugging conversation flow,
/// streaming operations, tool execution, and state transitions.
class ConversationLogger {
    // MARK: - Singleton
    static let shared = ConversationLogger()
    
    // MARK: - Backend Logger
    private let osLogger = Logger(subsystem: "com.trainer.app", category: "Conversation")
    
    // MARK: - Configuration
    
    /// Enable/disable debug-level logging (should be false in production)
    /// Note: warnings and errors always emit regardless of this setting
    var isDebugMode: Bool = true
    
    /// Minimum log level to display (default: .info so warnings/errors always show)
    var minimumLevel: LogLevel = .info
    
    // MARK: - Log Levels
    
    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
        
        var name: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Event Types
    
    enum StreamingEvent {
        case started
        case tokenReceived(count: Int)
        case reasoningReceived(length: Int)
        case toolDetected(name: String)
        case messageCreated(index: Int)
        case messageUpdated(index: Int)
        case completed
        case failed(error: String)
        
        var description: String {
            switch self {
            case .started:
                return "Streaming started"
            case .tokenReceived(let count):
                return "Token received (buffer: \(count))"
            case .reasoningReceived(let length):
                return "Reasoning chunk received (total: \(length))"
            case .toolDetected(let name):
                return "Tool detected: \(name)"
            case .messageCreated(let index):
                return "Message created at index \(index)"
            case .messageUpdated(let index):
                return "Message updated at index \(index)"
            case .completed:
                return "Streaming completed"
            case .failed(let error):
                return "Streaming failed: \(error)"
            }
        }
    }
    
    // MARK: - Private Init
    private init() {}
    
    // MARK: - Public Logging Methods
    
    /// General-purpose logging
    func log(_ level: LogLevel, _ message: String, context: String? = nil) {
        // Warnings and errors: always emit (bypass all checks)
        // Info: honor minimumLevel only (can be enabled in production)
        // Debug: honor minimumLevel AND isDebugMode (debug builds only)
        
        let contextStr = context.map { "[\($0)] " } ?? ""
        let fullMessage = "\(contextStr)\(message)"
        
        if level >= .warning {
            // Always log warnings and errors
            switch level {
            case .error:
                osLogger.error("\(fullMessage, privacy: .public)")
            case .warning:
                osLogger.warning("\(fullMessage, privacy: .public)")
            default:
                break
            }
        } else if level == .info {
            // Info respects minimumLevel but not isDebugMode
            guard level >= minimumLevel else { return }
            osLogger.info("\(fullMessage, privacy: .public)")
        } else {
            // Debug requires both minimumLevel and isDebugMode
            guard level >= minimumLevel && isDebugMode else { return }
            osLogger.debug("\(fullMessage, privacy: .public)")
        }
    }
    
    /// Log a streaming event
    func logStreamingEvent(_ event: StreamingEvent) {
        log(.debug, event.description, context: "Streaming")
    }
    
    /// Log tool execution
    func logToolExecution(_ toolName: String, result: String) {
        log(.info, "Tool '\(toolName)' executed: \(result)", context: "Tools")
    }
    
    /// Log state transition
    func logStateTransition(from: String, to: String) {
        log(.debug, "State: \(from) → \(to)", context: "State")
    }
    
    /// Log conversation flow milestone
    func logFlowMilestone(_ milestone: String) {
        log(.info, milestone, context: "Flow")
    }
    
    /// Log timing information
    func logTiming(_ label: String, timestamp: TimeInterval) {
        log(.debug, "\(label): \(timestamp)", context: "Timing")
    }
    
    /// Log response processing
    func logResponse(_ event: ResponseEvent) {
        log(.debug, event.description, context: "Response")
    }
    
    /// Log persistence operations
    func logPersistence(_ operation: String, messageCount: Int) {
        log(.debug, "\(operation) with \(messageCount) messages", context: "Persistence")
    }
    
    /// Log errors with full context
    func logError(_ error: Error, context: String? = nil) {
        log(.error, error.localizedDescription, context: context)
    }
    
    // MARK: - Response Events
    
    enum ResponseEvent {
        case preparingResponse
        case receivedResponse(length: Int)
        case processedResponse(cleaned: Int, hasTools: Bool)
        case generatedFallback
        case finalized
        
        var description: String {
            switch self {
            case .preparingResponse:
                return "Preparing response"
            case .receivedResponse(let length):
                return "Received response (length: \(length))"
            case .processedResponse(let cleaned, let hasTools):
                return "Processed response (cleaned: \(cleaned), hasTools: \(hasTools))"
            case .generatedFallback:
                return "Generated fallback response"
            case .finalized:
                return "Response finalized"
            }
        }
    }
}