import Foundation

// MARK: - Hybrid Cloud Store (Tier 2)

/// Hybrid storage that syncs between iCloud Key-Value Store and UserDefaults
/// Use for: Training programs, workout plans, workout results - user data that syncs across devices
final class HybridCloudStore<T: Codable>: PersistenceStore, CloudSyncable {
    typealias Value = T
    
    private let userDefaults: UserDefaults
    private let iCloudStore: NSUbiquitousKeyValueStore
    private let keyPrefix: String
    let useICloud: Bool
    
    /// Closure called when iCloud data changes externally
    var onCloudChange: (() -> Void)?
    
    /// Initialize a hybrid cloud store
    /// - Parameters:
    ///   - keyPrefix: Prefix for all keys (e.g., "workout_")
    ///   - userDefaults: UserDefaults instance (default: .standard)
    ///   - iCloudStore: iCloud KV store instance (default: .default)
    init(keyPrefix: String = "", 
         userDefaults: UserDefaults = .standard,
         iCloudStore: NSUbiquitousKeyValueStore = .default) {
        self.keyPrefix = keyPrefix
        self.userDefaults = userDefaults
        self.iCloudStore = iCloudStore
        self.useICloud = FileManager.default.ubiquityIdentityToken != nil
        
        if useICloud {
            setupCloudSync()
        } else {
            print("⚠️ HybridCloudStore: iCloud not available for prefix '\(keyPrefix)'")
        }
    }
    
    deinit {
        if useICloud {
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // MARK: - Cloud Sync Setup
    
    private func setupCloudSync() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudChange(notification)
        }
        
        // Initial sync
        iCloudStore.synchronize()
        print("✅ HybridCloudStore: iCloud sync enabled for prefix '\(keyPrefix)'")
    }
    
    @objc private func handleCloudChange(_ notification: Notification) {
        print("📱 HybridCloudStore: iCloud data changed for prefix '\(keyPrefix)'")
        onCloudChange?()
    }
    
    // MARK: - PersistenceStore Protocol
    
    func save(_ value: T, forKey key: String) throws {
        let fullKey = makeFullKey(key)
        
        do {
            let data = try JSONEncoder().encode(value)
            
            // ALWAYS save locally first
            userDefaults.set(data, forKey: fullKey)
            
            // Then sync to iCloud if available
            if useICloud {
                iCloudStore.set(data, forKey: fullKey)
                _ = iCloudStore.synchronize()
                print("☁️ HybridCloudStore: Saved '\(fullKey)' to iCloud (\(data.count) bytes)")
            } else {
                print("💾 HybridCloudStore: Saved '\(fullKey)' locally only")
            }
        } catch {
            throw PersistenceError.encodingFailed("HybridCloudStore: \(error.localizedDescription)")
        }
    }
    
    func load(forKey key: String) -> T? {
        let fullKey = makeFullKey(key)
        
        // Try iCloud first if available
        if useICloud, let data = iCloudStore.data(forKey: fullKey) {
            if let value = try? JSONDecoder().decode(T.self, from: data) {
                print("📥 HybridCloudStore: Loaded '\(fullKey)' from iCloud")
                return value
            } else {
                print("⚠️ HybridCloudStore: Failed to decode iCloud data for '\(fullKey)'")
            }
        }
        
        // Fallback to local storage
        if let data = userDefaults.data(forKey: fullKey) {
            if let value = try? JSONDecoder().decode(T.self, from: data) {
                print("📱 HybridCloudStore: Loaded '\(fullKey)' from local storage")
                return value
            } else {
                print("⚠️ HybridCloudStore: Failed to decode local data for '\(fullKey)'")
            }
        }
        
        return nil
    }
    
    func delete(forKey key: String) throws {
        let fullKey = makeFullKey(key)
        
        // Remove from both locations
        userDefaults.removeObject(forKey: fullKey)
        
        if useICloud {
            iCloudStore.removeObject(forKey: fullKey)
            _ = iCloudStore.synchronize()
            print("🗑️ HybridCloudStore: Deleted '\(fullKey)' from both locations")
        } else {
            print("🗑️ HybridCloudStore: Deleted '\(fullKey)' from local storage")
        }
    }
    
    func exists(forKey key: String) -> Bool {
        let fullKey = makeFullKey(key)
        
        // Check iCloud first if available
        if useICloud, iCloudStore.data(forKey: fullKey) != nil {
            return true
        }
        
        // Check local storage
        return userDefaults.data(forKey: fullKey) != nil
    }
    
    func clear() throws {
        // Note: Clearing all keys with a prefix is complex
        // For now, this requires manual key tracking or external iteration
        throw PersistenceError.clearFailed("HybridCloudStore: Clear requires iterating all known keys")
    }
    
    // MARK: - CloudSyncable Protocol
    
    @discardableResult
    func synchronize() -> Bool {
        return useICloud ? iCloudStore.synchronize() : false
    }
    
    // MARK: - Helper Methods
    
    private func makeFullKey(_ key: String) -> String {
        return keyPrefix.isEmpty ? key : "\(keyPrefix)\(key)"
    }
}

// MARK: - Date-Keyed Extension

extension HybridCloudStore: DateKeyedStore {
    
    /// Generate a standardized date key (yyyy-MM-dd in UTC)
    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")  // CRITICAL: Always UTC
        return formatter.string(from: date)
    }
    
    /// Save a value for a specific date
    func save(_ value: T, for date: Date) throws {
        try save(value, forKey: dateKey(for: date))
    }
    
    /// Load a value for a specific date
    func load(for date: Date) -> T? {
        return load(forKey: dateKey(for: date))
    }
    
    /// Delete a value for a specific date
    func delete(for date: Date) throws {
        try delete(forKey: dateKey(for: date))
    }
    
    /// Clear a range of dates
    func clearRange(from startDate: Date, to endDate: Date) throws {
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate <= endDate {
            try delete(for: currentDate)
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        // Ensure iCloud sync after bulk deletion
        if useICloud {
            _ = iCloudStore.synchronize()
        }
        
        print("🧹 HybridCloudStore: Cleared date range from \(dateKey(for: startDate)) to \(dateKey(for: endDate))")
    }
}