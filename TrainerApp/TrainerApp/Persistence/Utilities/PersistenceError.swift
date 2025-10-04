import Foundation

// MARK: - Persistence Errors

/// Errors that can occur during persistence operations
enum PersistenceError: LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)
    case saveFailed(String)
    case loadFailed(String)
    case deleteFailed(String)
    case clearFailed(String)
    case invalidKey(String)
    case iCloudUnavailable
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed(let context):
            return "Failed to encode data: \(context)"
        case .decodingFailed(let context):
            return "Failed to decode data: \(context)"
        case .saveFailed(let context):
            return "Failed to save data: \(context)"
        case .loadFailed(let context):
            return "Failed to load data: \(context)"
        case .deleteFailed(let context):
            return "Failed to delete data: \(context)"
        case .clearFailed(let context):
            return "Failed to clear data: \(context)"
        case .invalidKey(let key):
            return "Invalid storage key: \(key)"
        case .iCloudUnavailable:
            return "iCloud Key-Value Store is not available"
        case .fileSystemError(let context):
            return "File system error: \(context)"
        }
    }
}