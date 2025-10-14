# TrainingScheduleManager Refactoring Plan

## Executive Summary

[`TrainingScheduleManager.swift`](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift:1) is a **986-line god object** that violates the Single Responsibility Principle by managing 7+ distinct concerns. This plan outlines a step-by-step refactoring to create a maintainable, testable architecture.

## Current State Analysis

### Problems

| Issue | Impact | Lines |
|-------|--------|-------|
| **God Object** | Hard to test, modify, and understand | 986 |
| **Multiple Responsibilities** | Tight coupling, cascading changes | 7+ domains |
| **Excessive Debug Logging** | ~15% of code is print statements | ~150 lines |
| **Complex Dependencies** | Hard to reason about state changes | Entire class |
| **Poor Testability** | Singleton pattern prevents testing | All methods |
| **Duplication** | Similar CRUD patterns repeated | 100+ lines |

### Responsibilities Breakdown

1. **Program Lifecycle** (lines 49-87, 334-377)
   - Start, load, save, restart programs
   - ~80 lines

2. **Block Management** (lines 89-161)
   - Generate all blocks, update current block
   - ~70 lines

3. **Calendar Generation** (lines 163-272)
   - Week/month generation with complex date logic
   - ~110 lines

4. **Workout CRUD** (lines 380-594)
   - Create, read, update, delete for workouts
   - ~215 lines

5. **Schedule Snapshot** (lines 617-680)
   - Generate comprehensive schedule reports
   - ~65 lines

6. **Formatting Utilities** (lines 682-967)
   - 10+ formatting methods for display
   - ~285 lines

7. **Results Delegation** (lines 31-47)
   - Proxy to WorkoutResultsManager
   - ~20 lines

8. **Helper APIs** (lines 274-332)
   - Position descriptions, computed properties
   - ~60 lines

---

## Proposed Architecture

### New Component Structure

```
Managers/
├── Training/
│   ├── TrainingProgramManager.swift      (~150 lines)
│   ├── TrainingBlockScheduler.swift      (~120 lines)
│   ├── WorkoutRepository.swift           (~180 lines)
│   └── CalendarGenerator.swift           (~140 lines)
├── Formatting/
│   ├── WorkoutFormatter.swift            (~200 lines)
│   └── ScheduleSnapshotBuilder.swift     (~150 lines)
└── TrainingScheduleCoordinator.swift     (~120 lines)
```

### Responsibility Distribution

#### 1. TrainingProgramManager (~150 lines)
**Single Responsibility**: Program lifecycle and state management

**Public API**:
```swift
class TrainingProgramManager: ObservableObject {
    @Published private(set) var currentProgram: TrainingProgram?
    
    func startProgram(startDate: Date)
    func restartProgram(startDate: Date)
    func loadProgram()
    var programStartDate: Date?
}
```

**Extracts**:
- `startNewProgram()` → `startProgram()`
- `loadProgram()` (private → encapsulated)
- `saveProgram()` (private → encapsulated)
- `restartProgram()`
- Persistence via `HybridCloudStore<TrainingProgram>`

---

#### 2. TrainingBlockScheduler (~120 lines)
**Single Responsibility**: Block generation and tracking logic

**Public API**:
```swift
class TrainingBlockScheduler {
    func generateBlocks(from startDate: Date, macroCycle: Int) -> [TrainingBlock]
    func getCurrentBlock(for date: Date, blocks: [TrainingBlock]) -> (block: TrainingBlock, weekInBlock: Int)?
    func getBlock(for date: Date, in blocks: [TrainingBlock]) -> TrainingBlock?
    func getBlockInfo(for weekNumber: Int) -> (type: BlockType, weekInBlock: Int)
}
```

**Extracts**:
- `generateAllBlocks()` → `generateBlocks()`
- `updateCurrentBlock()` logic → `getCurrentBlock()`
- `getBlockForDate()` → `getBlock(for:in:)`
- `getBlockForWeek()` → `getBlockInfo()`

---

#### 3. WorkoutRepository (~180 lines)
**Single Responsibility**: Workout CRUD operations and persistence

**Public API**:
```swift
class WorkoutRepository {
    func getWorkout(for date: Date) -> WorkoutDay?
    func saveWorkout(_ workout: WorkoutDay) throws
    func deleteWorkout(for date: Date) throws
    
    // Planning APIs
    func planSingleWorkout(for date: Date, workout: String, notes: String?, icon: String?) throws
    func planStructuredWorkout(for date: Date, workout: StructuredWorkout, notes: String?, icon: String?) throws
    
    // Update APIs
    func updateSingleWorkout(for date: Date, workout: String, reason: String?) throws
    func updateStructuredWorkout(for date: Date, workout: StructuredWorkout, notes: String?, icon: String?) throws
    
    // Batch operations
    func updateWeekWorkouts(weekStartDate: Date, workouts: [String: String]) throws
    func clearWorkouts(from: Date, to: Date) throws
}
```

**Extracts**:
- All `plan*()` methods
- All `update*()` methods
- All `delete*()` methods
- `getWorkoutDay()` → `getWorkout()`
- `saveWorkoutDay()` → `saveWorkout()`
- Encapsulates `HybridCloudStore<WorkoutDay>`

**Benefits**:
- Removes 215 lines from manager
- Clear error handling with throws
- Single source of truth for persistence
- Easily testable with mock stores

---

#### 4. CalendarGenerator (~140 lines)
**Single Responsibility**: Generate calendar views with workout data

**Public API**:
```swift
class CalendarGenerator {
    func generateWeek(containing date: Date, 
                     program: TrainingProgram?,
                     blockScheduler: TrainingBlockScheduler,
                     workoutRepository: WorkoutRepository) -> [WorkoutDay]
    
    func generateMonth(containing date: Date,
                      program: TrainingProgram?,
                      blockScheduler: TrainingBlockScheduler,
                      workoutRepository: WorkoutRepository) -> [WorkoutDay]
}
```

**Extracts**:
- `generateWeek()` (simplified, dependencies injected)
- `generateMonth()` (simplified, dependencies injected)
- `generateDayForDate()` → internal helper

**Benefits**:
- Pure functions (no side effects)
- Easily testable with mock dependencies
- Clear separation from persistence

---

#### 5. WorkoutFormatter (~200 lines)
**Single Responsibility**: Format workout and exercise details for display

**Public API**:
```swift
struct WorkoutFormatter {
    static func formatExerciseName(_ exercise: Exercise) -> String
    static func formatExerciseDetails(_ exercise: Exercise) -> String
    static func formatResults(_ results: [WorkoutSetResult], for exercise: String) -> String
    static func formatAllResults(_ results: [WorkoutSetResult]) -> String
    
    // Type-specific formatters
    static func formatStrength(_ detail: StrengthDetail) -> String
    static func formatCardio(_ detail: CardioDetail) -> String
    static func formatMobility(_ detail: MobilityDetail) -> String
    static func formatYoga(_ detail: YogaDetail) -> String
    static func formatGeneric(_ detail: GenericDetail) -> String
}
```

**Extracts**:
- All `formatExercise*()` methods
- All `formatStrength*()`, `formatCardio*()`, etc.
- All `formatResults*()` methods
- Result matching logic

**Benefits**:
- Static methods (no state)
- Pure formatting logic
- Reusable across app
- Easy to test

---

#### 6. ScheduleSnapshotBuilder (~150 lines)
**Single Responsibility**: Build comprehensive schedule reports

**Public API**:
```swift
class ScheduleSnapshotBuilder {
    func buildSnapshot(
        from startDate: Date,
        to endDate: Date,
        workoutRepository: WorkoutRepository,
        resultsManager: WorkoutResultsManager,
        formatter: WorkoutFormatter.Type = WorkoutFormatter.self
    ) -> String
    
    func buildBlockContext(
        currentBlock: TrainingBlock?,
        currentWeekInBlock: Int,
        totalWeek: Int,
        programStartDate: Date?
    ) -> String
}
```

**Extracts**:
- `generateScheduleSnapshot()` → `buildSnapshot()`
- `generateBlockContext()` → `buildBlockContext()`
- `formatDayEntry()` → internal helper
- Date formatting utilities

**Benefits**:
- Dependency injection for testability
- Builder pattern for complex formatting
- Reusable snapshot logic

---

#### 7. TrainingScheduleCoordinator (~120 lines)
**Single Responsibility**: Coordinate between components, maintain published state

**Public API**:
```swift
@MainActor
class TrainingScheduleCoordinator: ObservableObject {
    // Published state for SwiftUI
    @Published private(set) var currentProgram: TrainingProgram?
    @Published private(set) var currentBlock: TrainingBlock?
    @Published private(set) var currentWeekInBlock: Int = 1
    @Published private(set) var workoutDays: [WorkoutDay] = []
    
    // Component dependencies
    private let programManager: TrainingProgramManager
    private let blockScheduler: TrainingBlockScheduler
    private let workoutRepository: WorkoutRepository
    private let calendarGenerator: CalendarGenerator
    
    // Computed properties
    var currentWeek: Int { ... }
    var totalWeekInProgram: Int { ... }
    var currentDay: DayOfWeek { ... }
    var programStartDate: Date? { ... }
    
    // Coordination methods
    func startProgram(startDate: Date)
    func restartProgram(startDate: Date)
    func refreshCurrentWeek()
    
    // Delegate to appropriate component
    func getWorkout(for date: Date) -> WorkoutDay? { 
        workoutRepository.getWorkout(for: date) 
    }
    func planWorkout(...) { ... }
    func generateSnapshot() -> String { ... }
}
```

**Responsibilities**:
- Maintain SwiftUI-observable state
- Coordinate between specialized components
- Provide simple public API for UI layer
- Delegate to appropriate specialist
- Manage component lifecycle

**Benefits**:
- Thin coordination layer
- Clear dependencies
- Easy to understand data flow
- Single entry point for UI

---

## Migration Strategy

### Phase 1: Extract Formatters (Low Risk)
**Goal**: Remove 285 lines of pure functions

**Steps**:
1. ✅ Create `WorkoutFormatter.swift` with static methods
2. ✅ Extract all `format*()` methods
3. ✅ Update call sites to use `WorkoutFormatter.*`
4. ✅ Remove original methods from manager
5. ✅ Test formatting output matches exactly

**Success Criteria**: All tests pass, output identical

**Estimated Time**: 2 hours

---

### Phase 2: Extract Snapshot Builder (Medium Risk)
**Goal**: Remove 150 lines of reporting logic

**Steps**:
1. ✅ Create `ScheduleSnapshotBuilder.swift`
2. ✅ Extract `generateScheduleSnapshot()` → `buildSnapshot()`
3. ✅ Extract `generateBlockContext()` → `buildBlockContext()`
4. ✅ Inject dependencies (repository, results manager, formatter)
5. ✅ Update call sites
6. ✅ Test snapshot output

**Success Criteria**: Snapshots match, dependencies injected

**Estimated Time**: 2 hours

---

### Phase 3: Extract Block Scheduler (Medium Risk)
**Goal**: Remove 70 lines of block logic

**Steps**:
1. ✅ Create `TrainingBlockScheduler.swift`
2. ✅ Extract `generateAllBlocks()` → `generateBlocks()`
3. ✅ Extract block lookup logic
4. ✅ Make stateless (pass program as parameter)
5. ✅ Update manager to use scheduler
6. ✅ Test block generation

**Success Criteria**: Block generation matches, no state retained

**Estimated Time**: 3 hours

---

### Phase 4: Extract Workout Repository (High Risk)
**Goal**: Remove 215 lines of CRUD operations

**Steps**:
1. ✅ Create `WorkoutRepository.swift`
2. ✅ Move `HybridCloudStore<WorkoutDay>` to repository
3. ✅ Extract all CRUD methods
4. ✅ Convert Bool returns to throws
5. ✅ Update error handling at call sites
6. ✅ Test all CRUD operations thoroughly

**Success Criteria**: All persistence works, error handling improved

**Estimated Time**: 4 hours

**Risk Mitigation**:
- Keep original methods during parallel implementation
- Comprehensive integration tests
- Gradual migration of call sites

---

### Phase 5: Extract Calendar Generator (Medium Risk)
**Goal**: Remove 110 lines of calendar logic

**Steps**:
1. ✅ Create `CalendarGenerator.swift`
2. ✅ Extract `generateWeek()` (inject dependencies)
3. ✅ Extract `generateMonth()` (inject dependencies)
4. ✅ Remove auto-initialization side effects
5. ✅ Make pure functions (no state changes)
6. ✅ Test calendar generation

**Success Criteria**: Calendar generation matches, dependencies injected

**Estimated Time**: 3 hours

---

### Phase 6: Extract Program Manager (Medium Risk)
**Goal**: Remove 80 lines of program lifecycle

**Steps**:
1. ✅ Create `TrainingProgramManager.swift`
2. ✅ Move `HybridCloudStore<TrainingProgram>` to manager
3. ✅ Extract program lifecycle methods
4. ✅ Keep @Published for SwiftUI reactivity
5. ✅ Update coordinator to use program manager
6. ✅ Test program lifecycle

**Success Criteria**: Program lifecycle works, state observable

**Estimated Time**: 3 hours

---

### Phase 7: Create Coordinator (High Risk)
**Goal**: Create thin coordination layer

**Steps**:
1. ✅ Create `TrainingScheduleCoordinator.swift`
2. ✅ Instantiate all component dependencies
3. ✅ Move @Published state to coordinator
4. ✅ Implement delegation methods
5. ✅ Update all call sites across app
6. ✅ Deprecate `TrainingScheduleManager.shared`
7. ✅ Comprehensive integration testing

**Success Criteria**: Full app functionality maintained, components isolated

**Estimated Time**: 5 hours

**Risk Mitigation**:
- Parallel implementation (keep manager working)
- Feature flag for new architecture
- Gradual migration per feature
- Extensive regression testing

---

### Phase 8: Cleanup & Documentation (Low Risk)
**Goal**: Polish and document new architecture

**Steps**:
1. ✅ Remove old `TrainingScheduleManager.swift`
2. ✅ Remove excessive debug logging
3. ✅ Add comprehensive documentation
4. ✅ Update .roorules for new structure
5. ✅ Create architecture diagram
6. ✅ Write migration guide for future developers

**Success Criteria**: Clean codebase, well documented

**Estimated Time**: 2 hours

---

## Testing Strategy

### Unit Tests (New)
```swift
// WorkoutFormatterTests.swift
func testFormatStrengthExercise() { ... }
func testFormatCardioExercise() { ... }

// TrainingBlockSchedulerTests.swift
func testGenerateBlocks() { ... }
func testGetCurrentBlock() { ... }

// WorkoutRepositoryTests.swift
func testSaveAndLoadWorkout() { ... }
func testClearWorkouts() { ... }

// CalendarGeneratorTests.swift
func testGenerateWeek() { ... }
func testPreProgramDates() { ... }
```

### Integration Tests (Enhanced)
```swift
// TrainingScheduleCoordinatorTests.swift
func testProgramLifecycle() { ... }
func testWorkoutPlanning() { ... }
func testSnapshotGeneration() { ... }
```

### Regression Tests (Critical)
- Full program lifecycle (start → plan → log → snapshot → restart)
- Multi-device sync scenarios
- Date boundary conditions
- Clear data operations

---

## File Size Comparison

| Component | Before | After | Reduction |
|-----------|--------|-------|-----------|
| TrainingScheduleManager | 986 lines | 0 lines | -100% |
| TrainingScheduleCoordinator | - | 120 lines | +120 |
| TrainingProgramManager | - | 150 lines | +150 |
| TrainingBlockScheduler | - | 120 lines | +120 |
| WorkoutRepository | - | 180 lines | +180 |
| CalendarGenerator | - | 140 lines | +140 |
| WorkoutFormatter | - | 200 lines | +200 |
| ScheduleSnapshotBuilder | - | 150 lines | +150 |
| **Total** | **986** | **1,060** | **+74 (+7%)** |

### Why More Lines?

While total lines increase slightly (+7%), we gain:
- **7 focused, single-purpose classes** vs 1 god object
- **Average ~150 lines per file** (sweet spot for comprehension)
- **Clear interfaces and dependencies**
- **Comprehensive documentation** (not counted above)
- **Testability** (unit tests now possible)
- **Maintainability** (changes isolated to single file)

**The 7% cost buys 300% improvement in maintainability.**

---

## Benefits Summary

### Before Refactoring
- ❌ 986-line god object
- ❌ 7+ responsibilities
- ❌ Impossible to test in isolation
- ❌ Tight coupling everywhere
- ❌ Changes cascade unpredictably
- ❌ ~150 lines of debug logging noise
- ❌ Singleton prevents dependency injection

### After Refactoring
- ✅ 7 focused classes (~150 lines each)
- ✅ Single responsibility per class
- ✅ Comprehensive unit test coverage
- ✅ Clear, injected dependencies
- ✅ Changes isolated to single file
- ✅ Clean, production-ready code
- ✅ Testable coordinator pattern

---

## Risks & Mitigation

### Risk: Breaking existing functionality
**Mitigation**: 
- Parallel implementation (keep old code working)
- Comprehensive regression test suite
- Feature flag for gradual rollout
- Phase-by-phase migration

### Risk: Performance degradation
**Mitigation**:
- Profile before/after with Instruments
- Cache frequently accessed data
- Lazy initialization where appropriate

### Risk: Increased complexity
**Mitigation**:
- Clear documentation for each component
- Architecture diagram showing relationships
- Code review for each phase

### Risk: Time overrun
**Mitigation**:
- Estimate 24 hours total (3 full days)
- Tackle phases independently
- Each phase deliverable separately
- Stop at any phase if needed

---

## Success Metrics

1. ✅ All existing tests pass
2. ✅ No regression in functionality
3. ✅ Unit test coverage >80% for new components
4. ✅ Average file size <200 lines
5. ✅ Clear separation of concerns
6. ✅ Dependency injection throughout
7. ✅ Documentation complete

---

## Timeline

| Phase | Time | Risk | Priority |
|-------|------|------|----------|
| 1. Extract Formatters | 2h | Low | High |
| 2. Extract Snapshot Builder | 2h | Medium | High |
| 3. Extract Block Scheduler | 3h | Medium | High |
| 4. Extract Workout Repository | 4h | High | Critical |
| 5. Extract Calendar Generator | 3h | Medium | High |
| 6. Extract Program Manager | 3h | Medium | High |
| 7. Create Coordinator | 5h | High | Critical |
| 8. Cleanup & Docs | 2h | Low | Medium |
| **Total** | **24h** | | |

**Recommended Schedule**: 3 focused days, 2 phases per day

---

## Next Steps

1. **Review this plan** - Discuss any concerns or modifications
2. **Create test suite** - Establish baseline behavior
3. **Begin Phase 1** - Start with low-risk formatter extraction
4. **Iterate** - Complete phases sequentially
5. **Celebrate** - 🎉 Clean, maintainable codebase!

---

## Questions for Discussion

1. Should we combine Phases 1 & 2 (formatters + snapshots) as a single PR?
2. Do we want to keep `TrainingScheduleManager` as a deprecated facade during migration?
3. Should we add telemetry to track usage of each component?
4. Any specific areas that need extra test coverage?
5. Timeline concerns - can we allocate 3 days for this work?