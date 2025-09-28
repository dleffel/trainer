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
        // Validate the result before saving
        try validateSetResult(result)
        
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
    
    // MARK: - Validation
    
    private func validateSetResult(_ result: WorkoutSetResult) throws {
        // Exercise name validation
        if result.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorkoutResultsError.invalidExerciseName
        }
        
        // RIR validation (0-10 scale)
        if let rir = result.rir, rir < 0 || rir > 10 {
            throw WorkoutResultsError.invalidRIR
        }
        
        // RPE validation (1-10 scale)
        if let rpe = result.rpe, rpe < 1 || rpe > 10 {
            throw WorkoutResultsError.invalidRPE
        }
        
        // Reps validation (must be positive)
        if let reps = result.reps, reps <= 0 {
            throw WorkoutResultsError.invalidReps
        }
        
        // Set number validation (must be positive)
        if let setNumber = result.setNumber, setNumber <= 0 {
            throw WorkoutResultsError.invalidSetNumber
        }
    }
}

// MARK: - Error Types

enum WorkoutResultsError: LocalizedError {
    case invalidExerciseName
    case invalidRIR
    case invalidRPE
    case invalidReps
    case invalidSetNumber
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidExerciseName:
            return "Exercise name cannot be empty"
        case .invalidRIR:
            return "RIR must be between 0 and 10"
        case .invalidRPE:
            return "RPE must be between 1 and 10"
        case .invalidReps:
            return "Reps must be a positive number"
        case .invalidSetNumber:
            return "Set number must be a positive number"
        case .encodingFailed:
            return "Failed to encode workout results"
        }
    }
}