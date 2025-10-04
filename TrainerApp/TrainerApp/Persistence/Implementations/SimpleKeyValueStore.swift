import Foundation

// MARK: - Simple Key-Value Store (Tier 1)

/// Simple UserDefaults wrapper for basic key-value storage
/// Use for: Settings, feature flags, API keys, simple primitives
final class SimpleKeyValueStore<T: Codable>: PersistenceStore {
    typealias Value = T
    
    private let userDefaults: UserDefaults
    private let keyPrefix: String
    
    /// Initialize a simple key-value store
    /// - Parameters:
    ///   - keyPrefix: Optional prefix for all keys (e.g., "Settings_")
    ///   - userDefaults: UserDefaults instance to use (default: .standard)
    init(keyPrefix: String = "", userDefaults: UserDefaults = .standard) {
        self.keyPrefix = keyPrefix
        self.userDefaults = userDefaults
    }
    
    // MARK: - PersistenceStore Protocol
    
    func save(_ value: T, forKey key: String) throws {
        let fullKey = makeFullKey(key)
        
        do {
            let data = try JSONEncoder().encode(value)
            userDefaults.set(data, forKey: fullKey)
        } catch {
            throw PersistenceError.encodingFailed("SimpleKeyValueStore: \(error.localizedDescription)")
        }
    }
    
    func load(forKey key: String) -> T? {
        let fullKey = makeFullKey(key)
        
        guard let data = userDefaults.data(forKey: fullKey) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("⚠️ SimpleKeyValueStore: Failed to decode value for key '\(fullKey)': \(error.localizedDescription)")
            return nil
        }
    }
    
    func delete(forKey key: String) throws {
        let fullKey = makeFullKey(key)
        userDefaults.removeObject(forKey: fullKey)
    }
    
    func exists(forKey key: String) -> Bool {
        let fullKey = makeFullKey(key)
        return userDefaults.object(forKey: fullKey) != nil
    }
    
    func clear() throws {
        // Note: Clearing requires knowing all keys with this prefix
        // For now, this is a no-op. Implement if needed by tracking keys.
        throw PersistenceError.clearFailed("SimpleKeyValueStore: Clear not fully implemented - delete keys individually")
    }
    
    // MARK: - Helper Methods
    
    private func makeFullKey(_ key: String) -> String {
        return keyPrefix.isEmpty ? key : "\(keyPrefix)\(key)"
    }
}

// MARK: - Convenience Extensions

extension SimpleKeyValueStore where T == String {
    /// Convenience method for saving strings directly
    func saveString(_ value: String, forKey key: String) throws {
        try save(value, forKey: key)
    }
    
    /// Convenience method for loading strings directly
    func loadString(forKey key: String) -> String? {
        return load(forKey: key)
    }
}

extension SimpleKeyValueStore where T == Bool {
    /// Convenience method for saving booleans directly
    func saveBool(_ value: Bool, forKey key: String) throws {
        try save(value, forKey: key)
    }
    
    /// Convenience method for loading booleans directly
    func loadBool(forKey key: String) -> Bool? {
        return load(forKey: key)
    }
}

extension SimpleKeyValueStore where T == Int {
    /// Convenience method for saving integers directly
    func saveInt(_ value: Int, forKey key: String) throws {
        try save(value, forKey: key)
    }
    
    /// Convenience method for loading integers directly
    func loadInt(forKey key: String) -> Int? {
        return load(forKey: key)
    }
}