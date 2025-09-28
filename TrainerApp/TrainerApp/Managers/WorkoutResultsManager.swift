import Foundation

/// Manages workout set results logging and persistence
class WorkoutResultsManager: ObservableObject {
    static let shared = WorkoutResultsManager()
    
    private let userDefaults = UserDefaults.standard
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let useICloud: Bool
    
    private init() {
        // Check if iCloud is available
        self.useICloud = FileManager.default.ubiquityIdentityToken != nil
        
        if useICloud {
            print("✅ iCloud available for WorkoutResultsManager")
            
            // Listen for iCloud changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleICloudChange),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: iCloudStore
            )
            
            // Sync immediately
            iCloudStore.synchronize()
        } else {
            print("⚠️ iCloud not available for WorkoutResultsManager")
        }
    }
    
    @objc private func handleICloudChange(_ notification: Notification) {
        print("📱 iCloud data changed for workout results")
        // Notify observers if needed
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Storage Key Management
    
    private struct StorageKeys {
        static let resultsPrefix = "workout_results_"
        
        static func resultsKey(for date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return "\(resultsPrefix)\(formatter.string(from: date))"
        }
    }
    
    // MARK: - Results Management
    
    /// Load all logged set results for a given date
    func loadSetResults(for date: Date) -> [WorkoutSetResult] {
        let key = StorageKeys.resultsKey(for: date)
        
        // Standardized storage access: try iCloud first if available, then local
        var data: Data?
        if useICloud {
            data = iCloudStore.data(forKey: key)
        }
        if data == nil {
            data = userDefaults.data(forKey: key)
        }
        
        guard let data = data,
              let results = try? JSONDecoder().decode([WorkoutSetResult].self, from: data) else {
            return []
        }
        return results
    }
    
    /// Append a set result for a given date; persists to UserDefaults and iCloud (when available)
    @discardableResult
    func appendSetResult(for date: Date, result: WorkoutSetResult) throws -> Bool {
        // Note: Validation is now handled in WorkoutSetResult's initializer
        
        var existing = loadSetResults(for: date)
        existing.append(result)
        
        guard let data = try? JSONEncoder().encode(existing) else {
            throw WorkoutResultsError.encodingFailed
        }
        
        let key = StorageKeys.resultsKey(for: date)
        
        // Save locally
        userDefaults.set(data, forKey: key)
        
        // Save to iCloud when enabled
        if useICloud {
            iCloudStore.set(data, forKey: key)
            iCloudStore.synchronize()
        }
        
        // Log successful save for debugging
        #if DEBUG
        print("🧾 Saved set: date=\(StorageKeys.resultsKey(for: date)), exercise=\(result.exerciseName), set=\(result.setNumber?.description ?? "-"), reps=\(result.reps?.description ?? "-"), lb=\(result.loadLb ?? "-"), kg=\(result.loadKg ?? "-"), rir=\(result.rir?.description ?? "-"), rpe=\(result.rpe?.description ?? "-")")
        #endif
        
        return true
    }
    
    /// Clear all results for a specific date range
    func clearResults(from startDate: Date, to endDate: Date) {
        let calendar = Calendar.current
        var currentDate = startDate
        
        while currentDate <= endDate {
            let key = StorageKeys.resultsKey(for: currentDate)
            
            // Clear from both storage locations
            userDefaults.removeObject(forKey: key)
            if useICloud {
                iCloudStore.removeObject(forKey: key)
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }
        
        if useICloud {
            iCloudStore.synchronize()
        }
    }
    
}

// MARK: - Error Types

enum WorkoutResultsError: LocalizedError {
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode workout results"
        }
    }
}