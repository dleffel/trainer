import Foundation

// MARK: - Base Persistence Protocol

/// Base protocol for all persistence operations
protocol PersistenceStore {
    associatedtype Value: Codable
    
    /// Save a value for a given key
    func save(_ value: Value, forKey key: String) throws
    
    /// Load a value for a given key
    func load(forKey key: String) -> Value?
    
    /// Delete a value for a given key
    func delete(forKey key: String) throws
    
    /// Check if a value exists for a given key
    func exists(forKey key: String) -> Bool
    
    /// Clear all data from this store
    func clear() throws
}

// MARK: - Cloud Sync Protocol

/// Protocol for stores that support iCloud sync
protocol CloudSyncable: PersistenceStore {
    /// Whether iCloud is available and being used
    var useICloud: Bool { get }
    
    /// Trigger a sync with iCloud
    @discardableResult
    func synchronize() -> Bool
}

// MARK: - Date-Keyed Store Protocol

/// Protocol for stores that use date-based keys
protocol DateKeyedStore: PersistenceStore {
    /// Generate a standardized date key
    func dateKey(for date: Date) -> String
    
    /// Save a value for a given date
    func save(_ value: Value, for date: Date) throws
    
    /// Load a value for a given date
    func load(for date: Date) -> Value?
    
    /// Delete a value for a given date
    func delete(for date: Date) throws
    
    /// Clear a range of dates
    func clearRange(from startDate: Date, to endDate: Date) throws
}