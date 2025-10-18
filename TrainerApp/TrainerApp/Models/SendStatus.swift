import Foundation

/// Tracks the send status of a message through the network layer
enum SendStatus: Codable, Equatable {
    case notSent        // User message pending send
    case sending        // API call in progress
    case sent           // Successfully sent
    case retrying(attempt: Int, maxAttempts: Int)
    case failed(reason: FailureReason, canRetry: Bool)
    case offline        // No network, will retry when online
    
    /// Reasons why a message send might fail
    enum FailureReason: String, Codable {
        case networkError
        case serverError
        case authenticationError
        case rateLimitError
        case timeout
        case unknown
        
        var userFriendlyMessage: String {
            switch self {
            case .networkError:
                return "Network connection lost"
            case .serverError:
                return "Server error, will retry"
            case .authenticationError:
                return "Authentication failed"
            case .rateLimitError:
                return "Rate limit exceeded, will retry"
            case .timeout:
                return "Request timed out"
            case .unknown:
                return "Unknown error occurred"
            }
        }
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case type, attempt, maxAttempts, reason, canRetry
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .notSent:
            try container.encode("notSent", forKey: .type)
        case .sending:
            try container.encode("sending", forKey: .type)
        case .sent:
            try container.encode("sent", forKey: .type)
        case .retrying(let attempt, let maxAttempts):
            try container.encode("retrying", forKey: .type)
            try container.encode(attempt, forKey: .attempt)
            try container.encode(maxAttempts, forKey: .maxAttempts)
        case .failed(let reason, let canRetry):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(canRetry, forKey: .canRetry)
        case .offline:
            try container.encode("offline", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "notSent":
            self = .notSent
        case "sending":
            self = .sending
        case "sent":
            self = .sent
        case "retrying":
            let attempt = try container.decode(Int.self, forKey: .attempt)
            let maxAttempts = try container.decode(Int.self, forKey: .maxAttempts)
            self = .retrying(attempt: attempt, maxAttempts: maxAttempts)
        case "failed":
            let reason = try container.decode(FailureReason.self, forKey: .reason)
            let canRetry = try container.decode(Bool.self, forKey: .canRetry)
            self = .failed(reason: reason, canRetry: canRetry)
        case "offline":
            self = .offline
        default:
            self = .notSent
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the message is in a state that allows retry
    var canRetry: Bool {
        switch self {
        case .failed(_, let canRetry):
            return canRetry
        case .offline:
            return true
        default:
            return false
        }
    }
    
    /// Whether the message is currently being processed
    var isActive: Bool {
        switch self {
        case .sending, .retrying:
            return true
        default:
            return false
        }
    }
    
    /// User-friendly status description
    var statusDescription: String {
        switch self {
        case .notSent:
            return "Pending"
        case .sending:
            return "Sending..."
        case .sent:
            return "Sent"
        case .retrying(let attempt, let max):
            return "Retrying (\(attempt)/\(max))"
        case .failed(let reason, _):
            return reason.userFriendlyMessage
        case .offline:
            return "Waiting for network"
        }
    }
    
    /// Icon name for UI display
    var iconName: String {
        switch self {
        case .notSent:
            return "clock"
        case .sending:
            return "arrow.up.circle"
        case .sent:
            return "checkmark.circle.fill"
        case .retrying:
            return "arrow.clockwise"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        }
    }
}