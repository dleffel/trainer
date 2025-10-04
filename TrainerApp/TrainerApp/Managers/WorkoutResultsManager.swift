import Foundation

/// Manages workout set results logging and persistence using HybridCloudStore
class WorkoutResultsManager: ObservableObject {
    static let shared = WorkoutResultsManager()
    
    // Use new Tier 2 persistence layer for synced workout results
    private let store: HybridCloudStore<[WorkoutSetResult]>
    
    private init() {
        // Initialize with centralized key prefix from PersistenceKey registry
        self.store = HybridCloudStore<[WorkoutSetResult]>(
            keyPrefix: PersistenceKey.Training.resultsPrefix
        )
        
        // Setup cloud change notification
        store.onCloudChange = { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        
        print("✅ WorkoutResultsManager initialized with HybridCloudStore (iCloud: \(store.useICloud))")
    }
    
    // MARK: - Public API
    
    /// Load all logged set results for a given date
    func loadSetResults(for date: Date) -> [WorkoutSetResult] {
        return store.load(for: date) ?? []
    }
    
    /// Append a set result for a given date; persists to UserDefaults and iCloud (when available)
    @discardableResult
    func appendSetResult(for date: Date, result: WorkoutSetResult) throws -> Bool {
        // Note: Validation is now handled in WorkoutSetResult's initializer
        
        var existing = loadSetResults(for: date)
        existing.append(result)
        
        do {
            try store.save(existing, for: date)
            
            // Log successful save for debugging
            #if DEBUG
            print("🧾 Saved set: date=\(store.dateKey(for: date)), exercise=\(result.exerciseName), set=\(result.setNumber?.description ?? "-"), reps=\(result.reps?.description ?? "-"), lb=\(result.loadLb ?? "-"), kg=\(result.loadKg ?? "-"), rir=\(result.rir?.description ?? "-"), rpe=\(result.rpe?.description ?? "-")")
            #endif
            
            return true
        } catch {
            throw WorkoutResultsError.saveFailed(error.localizedDescription)
        }
    }
    
    /// Clear all results for a specific date range
    func clearResults(from startDate: Date, to endDate: Date) {
        do {
            try store.clearRange(from: startDate, to: endDate)
            print("🧹 Cleared workout results from \(store.dateKey(for: startDate)) to \(store.dateKey(for: endDate))")
        } catch {
            print("❌ Failed to clear results: \(error.localizedDescription)")
        }
    }
}

// MARK: - Error Types

enum WorkoutResultsError: LocalizedError {
    case encodingFailed
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode workout results"
        case .saveFailed(let context):
            return "Failed to save workout results: \(context)"
        }
    }
}