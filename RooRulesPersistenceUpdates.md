# .roorules Persistence Section Updates

This document contains the new persistence section to be added to `.roorules`. This should be inserted after the "Data Model Changes" section.

---

## Data Persistence

### Storage Architecture

The TrainerApp uses a three-tier storage architecture. Choose the appropriate tier based on your data characteristics:

#### Tier 1: Simple Key-Value (UserDefaults)
**Use For:**
- Application settings and preferences
- Feature flags and toggles
- API keys and tokens
- Simple primitive values

**Characteristics:**
- Local storage only (no iCloud sync)
- Maximum ~1KB per value recommended
- Fast synchronous access
- Key pattern: Direct descriptive names

**Examples:**
- `OPENROUTER_API_KEY`
- `DeveloperModeEnabled`
- `APILoggingEnabled`

**Implementation:**
```swift
// Direct UserDefaults access for simple values
UserDefaults.standard.set(value, forKey: "SettingName")
let value = UserDefaults.standard.bool(forKey: "SettingName")
```

#### Tier 2: Synced Objects (Hybrid iCloud + UserDefaults)
**Use For:**
- User data that should sync across devices
- Training programs and schedules
- Workout plans and results
- Structured data that fits in iCloud KV store (<1MB)

**Characteristics:**
- Dual storage: iCloud KV Store + UserDefaults fallback
- Automatic cloud sync when available
- JSON encoding for Codable types
- Key pattern: Prefixed with domain (`TrainingProgram`, `workout_`, `workout_results_`)

**Examples:**
- Training program: `TrainingProgram`
- Workout days: `workout_yyyy-MM-dd`
- Workout results: `workout_results_yyyy-MM-dd`

**Implementation:**
```swift
// Use HybridCloudStore (once implemented)
let store = HybridCloudStore<WorkoutDay>(keyPrefix: "workout_")
try store.save(workoutDay, for: date)
let workout = store.load(for: date)
```

**Current Pattern (to be refactored):**
```swift
// Check iCloud first
var data: Data?
if useICloud {
    data = iCloudStore.data(forKey: key)
}
// Fallback to local
if data == nil {
    data = userDefaults.data(forKey: key)
}
// Decode and use
if let data = data {
    let object = try? JSONDecoder().decode(T.self, from: data)
}
```

#### Tier 3: File-Based Storage
**Use For:**
- Large datasets (logs, archives)
- Data requiring rotation/retention policies
- Conversation history with size management
- Any data >1MB

**Characteristics:**
- JSON files in Documents directory
- Supports archiving and compression
- Optional iCloud Drive sync (not KV store)
- Subdirectory organization

**Examples:**
- API logs: `Documents/APILogs/`
- Conversation backups: `Documents/conversation.json`

**Implementation:**
```swift
// Use LoggingPersistence pattern or FileStore (once implemented)
let logsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    .first!.appendingPathComponent("APILogs")
let data = try JSONEncoder().encode(object)
try data.write(to: fileURL, options: .atomic)
```

### Storage Key Naming Conventions

**CRITICAL:** All storage keys must follow these conventions to prevent collisions and ensure maintainability.

#### Key Patterns

1. **Simple Settings** (Tier 1)
   - Pattern: `DescriptiveSettingName`
   - Examples: `APILoggingEnabled`, `DeveloperModeEnabled`

2. **Domain Objects** (Tier 2)
   - Pattern: `DomainName` or `domain_prefix`
   - Examples: `TrainingProgram`, `workout_`, `workout_results_`

3. **Date-Keyed Data** (Tier 2)
   - Pattern: `prefix_yyyy-MM-dd`
   - Date format: ISO 8601 date only, UTC timezone
   - Examples: `workout_2024-01-15`, `workout_results_2024-01-15`

4. **File Paths** (Tier 3)
   - Pattern: `Subdirectory/filename.json`
   - Examples: `APILogs/api_logs.json`, `conversation.json`

#### Key Registry

Maintain all storage keys in a central registry (`PersistenceKey` enum once implemented):

```swift
enum PersistenceKey {
    enum Settings {
        static let apiKey = "OPENROUTER_API_KEY"
        static let developerMode = "DeveloperModeEnabled"
    }
    
    enum Training {
        static let program = "TrainingProgram"
        static let workoutPrefix = "workout_"
        static let resultsPrefix = "workout_results_"
    }
}
```

### Date Key Generation

**CRITICAL:** Date-based keys MUST use consistent formatting to prevent data loss.

**Required Pattern:**
```swift
private func dateKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")  // REQUIRED
    return formatter.string(from: date)
}
```

**Rules:**
- ✅ Always use `yyyy-MM-dd` format (ISO 8601 date only)
- ✅ Always force UTC timezone to prevent DST/timezone issues
- ✅ Use the same formatter instance across related operations
- ❌ Never use locale-dependent formats
- ❌ Never include time components in date keys

### iCloud Sync Pattern

When implementing iCloud sync, follow this standard pattern:

```swift
class Manager {
    private let userDefaults = UserDefaults.standard
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let useICloud: Bool
    
    init() {
        // Check iCloud availability
        self.useICloud = FileManager.default.ubiquityIdentityToken != nil
        
        if useICloud {
            // Setup change observer
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleICloudChange),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: iCloudStore
            )
            iCloudStore.synchronize()
        }
    }
    
    @objc private func handleICloudChange(_ notification: Notification) {
        // Handle external changes
        DispatchQueue.main.async {
            self.loadData()
        }
    }
    
    func save() {
        // Save locally first
        userDefaults.set(data, forKey: key)
        
        // Then sync to iCloud
        if useICloud {
            iCloudStore.set(data, forKey: key)
            iCloudStore.synchronize()
        }
    }
    
    func load() {
        // Try iCloud first
        if useICloud, let data = iCloudStore.data(forKey: key) {
            return data
        }
        // Fallback to local
        return userDefaults.data(forKey: key)
    }
}
```

### Data Clearing Best Practices

When implementing data clearing (e.g., "Clear Workout Data"):

**MUST DO:**
1. Clear from ALL storage locations (iCloud + UserDefaults)
2. Clear ALL related keys (use extended date range for safety)
3. Call synchronize() after iCloud operations
4. Update all relevant managers

**Pattern:**
```swift
func clearAllData() {
    // 1. Clear primary data
    if useICloud {
        iCloudStore.removeObject(forKey: primaryKey)
    }
    userDefaults.removeObject(forKey: primaryKey)
    
    // 2. Clear date-ranged data (use generous range)
    for i in -365...365 {
        if let date = Calendar.current.date(byAdding: .day, value: i, to: Date.current) {
            let key = "prefix_\(dateKey(for: date))"
            if useICloud {
                iCloudStore.removeObject(forKey: key)
            }
            userDefaults.removeObject(forKey: key)
        }
    }
    
    // 3. Synchronize iCloud
    if useICloud {
        iCloudStore.synchronize()
    }
    
    // 4. Notify related managers (if needed)
}
```

### Adding New Persisted Fields

When adding new fields to persisted models:

**REQUIRED STEPS:**
1. Add field to model with `Codable` conformance
2. Update `clearProgram()` or equivalent clearing method to remove new storage keys
3. Test that clearing removes ALL data including new fields
4. Add storage key to central registry (once implemented)
5. Consider migration strategy for existing users

**Example:**
```swift
// 1. Add to model
struct WorkoutDay: Codable {
    var newField: String?  // Added field
}

// 2. Update clearing method
func clearProgram() {
    // ... existing clearing code ...
    
    // Add clearing for new field's storage location
    for i in -365...365 {
        if let date = Calendar.current.date(byAdding: .day, value: i, to: Date.current) {
            let key = "new_field_\(dateKey(for: date))"
            userDefaults.removeObject(forKey: key)
            iCloudStore.removeObject(forKey: key)
        }
    }
}
```

### Testing Persistence

**Required Tests:**
1. ✅ Verify data saves to correct storage tier
2. ✅ Verify data loads from correct fallback order
3. ✅ Verify iCloud sync triggers properly
4. ✅ Verify date keys are timezone-independent
5. ✅ Verify complete data clearing (no orphaned keys)
6. ✅ Verify backward compatibility with existing data

### Migration Strategy (Future)

When the unified persistence layer is implemented:

1. **Phase 1**: Implement protocols and base stores
2. **Phase 2**: Migrate one manager as proof of concept
3. **Phase 3**: Ensure backward compatibility (same keys)
4. **Phase 4**: Roll out to remaining managers
5. **Phase 5**: Add versioning for future schema changes

**Backward Compatibility:**
- New stores MUST use same keys as existing implementation
- Data format MUST remain compatible (JSON encoding)
- Migration helper MUST convert any changed formats
- Test data loads correctly from both old and new code

---

## Summary of Rules

### DO:
- ✅ Use appropriate storage tier for your data type
- ✅ Follow key naming conventions strictly
- ✅ Use UTC timezone for all date-based keys
- ✅ Implement iCloud sync for user data (Tier 2)
- ✅ Always save locally + iCloud when available
- ✅ Always try iCloud first when loading
- ✅ Clear from ALL storage locations
- ✅ Update clearing methods when adding fields
- ✅ Register all keys centrally (once available)
- ✅ Test data clearing completely

### DON'T:
- ❌ Don't use direct UserDefaults for synced data
- ❌ Don't skip local storage fallback
- ❌ Don't use locale-dependent date formats
- ❌ Don't include timezone offsets in date keys
- ❌ Don't forget to synchronize iCloud after changes
- ❌ Don't leave orphaned keys when clearing data
- ❌ Don't assume iCloud is always available
- ❌ Don't exceed 1MB for iCloud KV store values