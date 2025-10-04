# Universal CRUD Persistence Architecture Plan

## Problem Statement

The TrainerApp currently has **inconsistent persistence patterns** across different managers:

### Current Patterns Identified

1. **TrainingScheduleManager**: UserDefaults + iCloud KeyValueStore
   - Key pattern: `TrainingProgram`, `workout_yyyy-MM-dd`
   - Dual storage with iCloud sync

2. **WorkoutResultsManager**: UserDefaults + iCloud KeyValueStore
   - Key pattern: `workout_results_yyyy-MM-dd`
   - Dual storage with iCloud sync

3. **ConversationPersistence**: iCloud KeyValueStore + Local JSON File
   - Key: `trainer_conversations`
   - File: `Documents/conversation.json`
   - Size-aware (1MB iCloud limit)

4. **LoggingPersistence**: Local JSON Files Only
   - Directory: `Documents/APILogs/`
   - File rotation, archiving, retention policies
   - No iCloud sync

5. **Simple Settings**: Direct UserDefaults
   - API keys, feature flags
   - No iCloud sync

### Key Issues

1. ❌ **No standard abstraction** - Each manager implements its own storage logic
2. ❌ **Duplicate code** - iCloud sync setup repeated across managers
3. ❌ **Inconsistent key naming** - Different prefixing strategies
4. ❌ **No central registry** - Hard to track storage keys
5. ❌ **Mixed data types** - Some use Codable in KV store, some use files
6. ❌ **No migration strategy** - No version handling for schema changes
7. ❌ **Inconsistent clearing** - Different approaches to data cleanup

---

## Proposed Architecture

### Core Principles

1. **Single Responsibility**: Each persistence mechanism serves a specific purpose
2. **Fallback Strategy**: Always have local backup for cloud data
3. **Type Safety**: Use protocols and generics for type-safe operations
4. **Testability**: All persistence should be mockable/injectable
5. **Consistency**: Standard patterns for CRUD operations
6. **Documentation**: Clear rules for when to use each mechanism

### Three-Tier Storage Strategy

```
┌─────────────────────────────────────────────────┐
│         Storage Tier Selection Guide            │
├─────────────────────────────────────────────────┤
│                                                 │
│  TIER 1: Simple Key-Value (UserDefaults)       │
│  ├─ Use For: Settings, flags, simple values    │
│  ├─ Max Size: < 1KB per value                  │
│  ├─ Sync: Local only                           │
│  └─ Examples: API keys, feature flags          │
│                                                 │
│  TIER 2: Synced Objects (Hybrid Storage)       │
│  ├─ Use For: User data, schedules, workouts    │
│  ├─ Max Size: < 1MB per object                 │
│  ├─ Sync: iCloud KV + UserDefaults fallback    │
│  └─ Examples: Training program, workout days   │
│                                                 │
│  TIER 3: Large/Complex Data (File-Based)       │
│  ├─ Use For: Logs, archives, large datasets    │
│  ├─ Max Size: Unlimited (managed)              │
│  ├─ Sync: Local files (optional CloudKit)      │
│  └─ Examples: API logs, conversation history   │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Core Persistence Protocols

Create a unified persistence protocol hierarchy:

```swift
// MARK: - Core Protocols

/// Base protocol for all persistence operations
protocol PersistenceStore {
    associatedtype Value: Codable
    
    func save(_ value: Value, forKey key: String) throws
    func load(forKey key: String) -> Value?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
    func clear() throws
}

/// Protocol for stores that support iCloud sync
protocol CloudSyncable: PersistenceStore {
    var useICloud: Bool { get }
    func synchronize() -> Bool
}

/// Protocol for stores with date-based keys
protocol DateKeyedStore: PersistenceStore {
    func dateKey(for date: Date) -> String
    func save(_ value: Value, for date: Date) throws
    func load(for date: Date) -> Value?
    func delete(for date: Date) throws
    func clearRange(from: Date, to: Date) throws
}
```

### Phase 2: Standard Implementations

Create concrete implementations for each tier:

#### 2.1 Simple Key-Value Store

```swift
/// Tier 1: Simple UserDefaults wrapper
final class SimpleKeyValueStore<T: Codable>: PersistenceStore {
    typealias Value = T
    
    private let userDefaults: UserDefaults
    private let keyPrefix: String
    
    init(keyPrefix: String, userDefaults: UserDefaults = .standard) {
        self.keyPrefix = keyPrefix
        self.userDefaults = userDefaults
    }
    
    func save(_ value: T, forKey key: String) throws {
        let fullKey = "\(keyPrefix)\(key)"
        let data = try JSONEncoder().encode(value)
        userDefaults.set(data, forKey: fullKey)
    }
    
    func load(forKey key: String) -> T? {
        let fullKey = "\(keyPrefix)\(key)"
        guard let data = userDefaults.data(forKey: fullKey) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    func delete(forKey key: String) throws {
        let fullKey = "\(keyPrefix)\(key)"
        userDefaults.removeObject(forKey: fullKey)
    }
    
    func exists(forKey key: String) -> Bool {
        let fullKey = "\(keyPrefix)\(key)"
        return userDefaults.object(forKey: fullKey) != nil
    }
    
    func clear() throws {
        // Clear all keys with this prefix
        // Implementation needed
    }
}
```

#### 2.2 Hybrid Cloud-Synced Store

```swift
/// Tier 2: Hybrid iCloud + UserDefaults storage
final class HybridCloudStore<T: Codable>: PersistenceStore, CloudSyncable {
    typealias Value = T
    
    private let userDefaults: UserDefaults
    private let iCloudStore: NSUbiquitousKeyValueStore
    private let keyPrefix: String
    let useICloud: Bool
    
    init(keyPrefix: String, 
         userDefaults: UserDefaults = .standard,
         iCloudStore: NSUbiquitousKeyValueStore = .default) {
        self.keyPrefix = keyPrefix
        self.userDefaults = userDefaults
        self.iCloudStore = iCloudStore
        self.useICloud = FileManager.default.ubiquityIdentityToken != nil
        
        if useICloud {
            setupCloudSync()
        }
    }
    
    private func setupCloudSync() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.handleCloudChange()
        }
        iCloudStore.synchronize()
    }
    
    func save(_ value: T, forKey key: String) throws {
        let fullKey = "\(keyPrefix)\(key)"
        let data = try JSONEncoder().encode(value)
        
        // Always save locally
        userDefaults.set(data, forKey: fullKey)
        
        // Save to iCloud if available
        if useICloud {
            iCloudStore.set(data, forKey: fullKey)
            _ = iCloudStore.synchronize()
        }
    }
    
    func load(forKey key: String) -> T? {
        let fullKey = "\(keyPrefix)\(key)"
        
        // Try iCloud first if available
        if useICloud, let data = iCloudStore.data(forKey: fullKey) {
            if let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
        }
        
        // Fallback to local storage
        if let data = userDefaults.data(forKey: fullKey) {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        
        return nil
    }
    
    func delete(forKey key: String) throws {
        let fullKey = "\(keyPrefix)\(key)"
        userDefaults.removeObject(forKey: fullKey)
        if useICloud {
            iCloudStore.removeObject(forKey: fullKey)
            _ = iCloudStore.synchronize()
        }
    }
    
    func synchronize() -> Bool {
        return iCloudStore.synchronize()
    }
    
    // Other methods...
}
```

#### 2.3 Date-Keyed Extension

```swift
/// Extension to add date-based key support
extension HybridCloudStore: DateKeyedStore {
    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    func save(_ value: T, for date: Date) throws {
        try save(value, forKey: dateKey(for: date))
    }
    
    func load(for date: Date) -> T? {
        return load(forKey: dateKey(for: date))
    }
    
    func delete(for date: Date) throws {
        try delete(forKey: dateKey(for: date))
    }
    
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
    }
}
```

#### 2.4 File-Based Store

```swift
/// Tier 3: File-based storage for large/complex data
final class FileStore<T: Codable>: PersistenceStore {
    typealias Value = T
    
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(subdirectory: String, fileManager: FileManager = .default) throws {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directory = documentsDir.appendingPathComponent(subdirectory)
        self.fileManager = fileManager
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    func save(_ value: T, forKey key: String) throws {
        let fileURL = directory.appendingPathComponent("\(key).json")
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
    
    func load(forKey key: String) -> T? {
        let fileURL = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
    
    func delete(forKey key: String) throws {
        let fileURL = directory.appendingPathComponent("\(key).json")
        try fileManager.removeItem(at: fileURL)
    }
    
    func exists(forKey key: String) -> Bool {
        let fileURL = directory.appendingPathComponent("\(key).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    func clear() throws {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            try fileManager.removeItem(at: file)
        }
    }
}
```

### Phase 3: Centralized Key Registry

Create a central place to manage all storage keys:

```swift
/// Central registry for all persistence keys
enum PersistenceKey {
    // MARK: - Settings (Tier 1)
    enum Settings {
        static let apiKey = "OPENROUTER_API_KEY"
        static let developerMode = "DeveloperModeEnabled"
        static let apiLogging = "APILoggingEnabled"
    }
    
    // MARK: - Training Data (Tier 2)
    enum Training {
        static let programPrefix = "TrainingProgram"
        static let workoutPrefix = "workout_"
        static let resultsPrefix = "workout_results_"
    }
    
    // MARK: - Conversations (Tier 2/3)
    enum Conversation {
        static let messages = "trainer_conversations"
    }
    
    // MARK: - Logging (Tier 3)
    enum Logging {
        static let apiLogsDirectory = "APILogs"
    }
}
```

### Phase 4: Migration & Refactoring Strategy

#### 4.1 Refactor Existing Managers

Update each manager to use the new persistence layer:

**TrainingScheduleManager** should use:
- `HybridCloudStore<TrainingProgram>` for program data
- `HybridCloudStore<WorkoutDay>` with `DateKeyedStore` for workouts

**WorkoutResultsManager** should use:
- `HybridCloudStore<[WorkoutSetResult]>` with `DateKeyedStore` for results

**ConversationPersistence** should use:
- `HybridCloudStore<[ChatMessage]>` or `FileStore<[ChatMessage]>` depending on size

**LoggingPersistence** can keep current implementation (Tier 3)

#### 4.2 Backward Compatibility

Ensure existing data is preserved:
1. New stores use same keys as current implementation
2. Migration helper to convert old data format if needed
3. Gradual rollout - one manager at a time

### Phase 5: Testing Strategy

1. **Unit Tests**: Test each store implementation independently
2. **Integration Tests**: Test manager refactoring with new stores
3. **Migration Tests**: Verify old data loads correctly
4. **Sync Tests**: Verify iCloud sync behavior
5. **Clear Tests**: Verify complete data cleanup

---

## Benefits

✅ **Consistency**: All persistence follows same patterns
✅ **Testability**: Easy to mock stores for testing
✅ **Type Safety**: Compile-time guarantees with generics
✅ **Maintainability**: Changes to persistence logic in one place
✅ **Discoverability**: Key registry shows all storage locations
✅ **Flexibility**: Easy to switch between storage tiers
✅ **Documentation**: Clear rules for when to use each tier

---

## .roorules Updates

Add comprehensive persistence guidelines to the rules file (see Phase 6 below).

---

## Next Steps

1. ✅ Review and approve this architecture plan
2. Create `TrainerApp/TrainerApp/Persistence/` directory structure
3. Implement core protocols and base stores
4. Refactor one manager as proof of concept (WorkoutResultsManager recommended)
5. Test and validate the approach
6. Roll out to remaining managers
7. Update documentation and .roorules

---

## Files to Create

```
TrainerApp/TrainerApp/Persistence/
├── Protocols/
│   ├── PersistenceStore.swift
│   ├── CloudSyncable.swift
│   └── DateKeyedStore.swift
├── Implementations/
│   ├── SimpleKeyValueStore.swift
│   ├── HybridCloudStore.swift
│   └── FileStore.swift
├── Utilities/
│   ├── PersistenceKey.swift
│   └── PersistenceError.swift
└── Extensions/
    └── HybridCloudStore+DateKeyed.swift
```

---

## Timeline Estimate

- **Phase 1-2**: 2-3 hours (Core protocols and implementations)
- **Phase 3**: 30 minutes (Key registry)
- **Phase 4**: 3-4 hours (Refactor managers)
- **Phase 5**: 2-3 hours (Testing)
- **Documentation**: 1 hour

**Total**: ~8-11 hours of development work