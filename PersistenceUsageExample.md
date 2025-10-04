# Persistence Layer Usage Examples

This document demonstrates how to use the new universal CRUD persistence architecture.

## Quick Reference

### Tier 1: Simple Settings (UserDefaults only)

```swift
// For simple settings, feature flags, API keys
let settingsStore = SimpleKeyValueStore<String>()

// Save
try settingsStore.save("my-api-key", forKey: PersistenceKey.Settings.apiKey)

// Load
if let apiKey = settingsStore.load(forKey: PersistenceKey.Settings.apiKey) {
    print("API Key: \(apiKey)")
}

// Delete
try settingsStore.delete(forKey: PersistenceKey.Settings.apiKey)
```

### Tier 2: Synced User Data (Hybrid iCloud + UserDefaults)

```swift
// For workout days, training programs, results
let workoutStore = HybridCloudStore<WorkoutDay>(keyPrefix: PersistenceKey.Training.workoutPrefix)

// Save for a specific date
let workoutDay = WorkoutDay(date: Date(), blockType: .hypertrophyStrength)
try workoutStore.save(workoutDay, for: Date())

// Load for a specific date
if let workout = workoutStore.load(for: Date()) {
    print("Workout: \(workout)")
}

// Delete for a specific date
try workoutStore.delete(for: Date())

// Clear a date range
let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
let endDate = Date()
try workoutStore.clearRange(from: startDate, to: endDate)

// Listen for iCloud changes
workoutStore.onCloudChange = {
    print("iCloud data changed - reload UI")
}
```

### Tier 3: Large Files (File-based storage)

```swift
// For logs, large datasets
let logStore = try FileStore<[APILogEntry]>(subdirectory: PersistenceKey.Logging.apiLogsDirectory)

// Save
let logs = [APILogEntry(...)]
try logStore.save(logs, forKey: "api_logs")

// Load
if let loadedLogs = logStore.load(forKey: "api_logs") {
    print("Loaded \(loadedLogs.count) log entries")
}

// List all files
let keys = logStore.listKeys()

// Get file size
if let size = logStore.fileSize(forKey: "api_logs") {
    print("File size: \(size) bytes")
}

// Archive old data
try logStore.archive(key: "api_logs")

// Clear all files
try logStore.clear()
```

## Refactored WorkoutResultsManager Example

```swift
import Foundation

/// Manages workout set results using the new persistence layer
class WorkoutResultsManager: ObservableObject {
    static let shared = WorkoutResultsManager()
    
    // Use HybridCloudStore for synced results
    private let store: HybridCloudStore<[WorkoutSetResult]>
    
    private init() {
        // Initialize with results prefix
        self.store = HybridCloudStore<[WorkoutSetResult]>(
            keyPrefix: PersistenceKey.Training.resultsPrefix
        )
        
        // Setup cloud change notification
        store.onCloudChange = { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Public API
    
    /// Load all logged set results for a given date
    func loadSetResults(for date: Date) -> [WorkoutSetResult] {
        return store.load(for: date) ?? []
    }
    
    /// Append a set result for a given date
    func appendSetResult(for date: Date, result: WorkoutSetResult) throws -> Bool {
        var existing = loadSetResults(for: date)
        existing.append(result)
        
        try store.save(existing, for: date)
        
        #if DEBUG
        print("🧾 Saved set: date=\(store.dateKey(for: date)), exercise=\(result.exerciseName)")
        #endif
        
        return true
    }
    
    /// Clear all results for a specific date range
    func clearResults(from startDate: Date, to endDate: Date) throws {
        try store.clearRange(from: startDate, to: endDate)
    }
}
```

## Migration Guide

### Before (Old Pattern)

```swift
class OldManager {
    private let userDefaults = UserDefaults.standard
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let useICloud: Bool
    
    init() {
        self.useICloud = FileManager.default.ubiquityIdentityToken != nil
        if useICloud {
            NotificationCenter.default.addObserver(...)
            iCloudStore.synchronize()
        }
    }
    
    func save(value: Data, key: String) {
        userDefaults.set(value, forKey: key)
        if useICloud {
            iCloudStore.set(value, forKey: key)
            iCloudStore.synchronize()
        }
    }
    
    func load(key: String) -> Data? {
        if useICloud, let data = iCloudStore.data(forKey: key) {
            return data
        }
        return userDefaults.data(forKey: key)
    }
}
```

### After (New Pattern)

```swift
class NewManager {
    private let store = HybridCloudStore<MyDataType>(keyPrefix: "my_prefix_")
    
    init() {
        store.onCloudChange = {
            // Handle changes
        }
    }
    
    func save(value: MyDataType, key: String) throws {
        try store.save(value, forKey: key)
    }
    
    func load(key: String) -> MyDataType? {
        return store.load(forKey: key)
    }
}
```

## Best Practices

### 1. Always use PersistenceKey registry
```swift
// ✅ GOOD
try store.save(value, forKey: PersistenceKey.Training.program)

// ❌ BAD
try store.save(value, forKey: "TrainingProgram")
```

### 2. Use UTC for date keys
```swift
// Date keys are automatically UTC in the stores
let workout = store.load(for: Date())  // UTC-safe
```

### 3. Handle errors properly
```swift
do {
    try store.save(value, forKey: key)
} catch let error as PersistenceError {
    print("Persistence error: \(error.localizedDescription)")
} catch {
    print("Unexpected error: \(error)")
}
```

### 4. Use appropriate tier for your data
- **Tier 1**: Settings < 1KB → `SimpleKeyValueStore`
- **Tier 2**: User data < 1MB → `HybridCloudStore`
- **Tier 3**: Large data > 1MB → `FileStore`

### 5. Listen for cloud changes
```swift
store.onCloudChange = { [weak self] in
    // Reload your data
    self?.loadData()
}
```

## Testing

```swift
func testPersistence() throws {
    let store = HybridCloudStore<WorkoutDay>(keyPrefix: "test_")
    
    // Save
    let workout = WorkoutDay(date: Date(), blockType: .hypertrophyStrength)
    try store.save(workout, for: Date())
    
    // Load
    let loaded = store.load(for: Date())
    XCTAssertEqual(loaded?.date, workout.date)
    
    // Delete
    try store.delete(for: Date())
    XCTAssertNil(store.load(for: Date()))
}
```

## Next Steps for Full Migration

1. ✅ Add persistence files to Xcode project (drag and drop Persistence folder)
2. ✅ Update `WorkoutResultsManager` to use `HybridCloudStore`
3. Update `TrainingScheduleManager` to use `HybridCloudStore`
4. Update `ConversationPersistence` to use `HybridCloudStore` or `FileStore`
5. Verify all data migrations work correctly
6. Test iCloud sync functionality
7. Remove old duplicate persistence code