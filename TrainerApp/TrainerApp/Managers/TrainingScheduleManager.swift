import Foundation

/// Coordinates training schedule components and maintains observable state for SwiftUI
/// This class acts as a thin coordination layer, delegating to specialized components:
/// - TrainingProgramManager: Program lifecycle
/// - TrainingBlockScheduler: Block generation and lookup
/// - WorkoutRepository: Workout CRUD operations
/// - CalendarGenerator: Week/month calendar views
/// - ScheduleSnapshotBuilder: Report generation
/// - WorkoutFormatter: Display formatting
class TrainingScheduleManager: ObservableObject {
    static let shared = TrainingScheduleManager()
    
    @Published var currentProgram: TrainingProgram?
    @Published var currentBlock: TrainingBlock?
    @Published var currentWeekInBlock: Int = 1
    @Published var workoutDays: [WorkoutDay] = []
    
    // Use new persistence layer for workout days
    private let workoutStore: HybridCloudStore<WorkoutDay>
    
    // Program manager for program lifecycle
    private let programManager: TrainingProgramManager
    
    // Block scheduler for training block management
    private let blockScheduler = TrainingBlockScheduler()
    
    // Workout repository for CRUD operations
    private lazy var workoutRepository: WorkoutRepository = {
        WorkoutRepository(workoutStore: workoutStore, blockScheduler: blockScheduler)
    }()
    
    // Snapshot builder for schedule reports
    private lazy var snapshotBuilder: ScheduleSnapshotBuilder = {
        ScheduleSnapshotBuilder(workoutStore: workoutStore)
    }()
    
    // Calendar generator for week/month views
    private lazy var calendarGenerator: CalendarGenerator = {
        CalendarGenerator(workoutStore: workoutStore, blockScheduler: blockScheduler)
    }()
    
    private init() {
        // Initialize stores
        let programStore = HybridCloudStore<TrainingProgram>()
        self.workoutStore = HybridCloudStore<WorkoutDay>(keyPrefix: PersistenceKey.Training.workoutPrefix)
        
        // Initialize program manager
        self.programManager = TrainingProgramManager(
            programStore: programStore,
            workoutStore: workoutStore
        )
        
        // Sync program state and setup change handler
        self.currentProgram = programManager.currentProgram
        programManager.onProgramChanged = { [weak self] in
            self?.currentProgram = self?.programManager.currentProgram
            self?.updateCurrentBlock()
        }
        
        // Trigger initial block update if we have a program
        if currentProgram != nil {
            updateCurrentBlock()
        }
    }
    
    // MARK: - Results Logging (Delegated to WorkoutResultsManager)
    
    /// Load all logged set results for a given date
    public func loadSetResults(for date: Date) -> [WorkoutSetResult] {
        return WorkoutResultsManager.shared.loadSetResults(for: date)
    }

    /// Append a set result for a given date; persists to UserDefaults and iCloud (when available)
    @discardableResult
    public func appendSetResult(for date: Date, result: WorkoutSetResult) -> Bool {
        do {
            return try WorkoutResultsManager.shared.appendSetResult(for: date, result: result)
        } catch {
            print("❌ Failed to save workout set result: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Program Management
    
    /// Start a new training program
    func startNewProgram(startDate: Date = Date.current) {
        programManager.startProgram(startDate: startDate)
    }
    
    /// Load existing program from storage
    private func loadProgram() {
        programManager.loadProgram()
    }
    
    /// Save program to storage
    private func saveProgram() {
        programManager.saveProgram()
    }
    
    // MARK: - Block Management
    
    /// Update the current training block based on the date
    private func updateCurrentBlock() {
        guard let program = currentProgram else {
            currentBlock = nil
            currentWeekInBlock = 1
            return
        }
        
        let blocks = blockScheduler.generateBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        let now = Date.current
        
        // Find the current block using scheduler
        if let (block, weekInBlock) = blockScheduler.getCurrentBlock(for: now, in: blocks) {
            self.currentBlock = block
            self.currentWeekInBlock = weekInBlock
        }
        
        // Generate current week's workout days (blank, to be filled by coach)
        workoutDays = generateWeek(containing: Date.current)
    }
    
    // MARK: - Calendar Generation
    
    /// Generate workout days for a specific week
    func generateWeek(containing date: Date) -> [WorkoutDay] {
        // Auto-initialize program if none exists
        if currentProgram == nil {
            loadProgram()
            
            if currentProgram == nil {
                let startDate = Calendar.current.startOfDay(for: Date.current)
                startNewProgram(startDate: startDate)
            }
        }
        
        guard let program = currentProgram else {
            return []
        }
        
        let blocks = blockScheduler.generateBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        return calendarGenerator.generateWeek(containing: date, program: program, blocks: blocks)
    }
    
    /// Generate workout days for a specific month
    func generateMonth(containing date: Date) -> [WorkoutDay] {
        guard let program = currentProgram else {
            return []
        }
        
        let blocks = blockScheduler.generateBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        return calendarGenerator.generateMonth(containing: date, program: program, blocks: blocks)
    }
    
    // MARK: - Helper Methods
    
    /// Get a formatted string describing the current position in the program
    func getCurrentPositionDescription() -> String {
        guard let block = currentBlock else {
            return "No active program"
        }
        
        return "\(block.type.rawValue) - Week \(currentWeekInBlock) of \(block.type.duration)"
    }
    
    // MARK: - Extended API for ToolProcessor
    
    /// Get the current program start date
    var programStartDate: Date? {
        return programManager.programStartDate
    }
    
    /// Get current week in the block
    var currentWeek: Int {
        guard let program = currentProgram else { return 1 }
        
        let weeksSinceStart = Calendar.current.dateComponents([.weekOfYear],
                                                              from: program.startDate,
                                                              to: Date.current).weekOfYear ?? 0
        let totalWeek = (weeksSinceStart % 20) + 1
        
        // Calculate week within current block
        if totalWeek <= 8 {
            return totalWeek
        } else if totalWeek == 9 {
            return 1
        } else if totalWeek <= 19 {
            return totalWeek - 9
        } else {
            return 1
        }
    }
    
    /// Get total week in program (1-20)
    var totalWeekInProgram: Int {
        guard let program = currentProgram else { return 1 }
        
        let weeksSinceStart = Calendar.current.dateComponents([.weekOfYear],
                                                              from: program.startDate,
                                                              to: Date.current).weekOfYear ?? 0
        return (weeksSinceStart % 20) + 1
    }
    
    /// Get current day of week
    var currentDay: DayOfWeek {
        return DayOfWeek.from(date: Date.current)
    }
    
    /// Get workout days for the current week
    var currentWeekDays: [WorkoutDay] {
        return generateWeek(containing: Date.current)
    }
    
    /// Start a new training program
    func startProgram(startDate: Date = Date.current) {
        programManager.startProgram(startDate: startDate)
    }
    
    /// Restart training program
    func restartProgram(startDate: Date = Date.current) {
        workoutDays = []
        programManager.restartProgram(startDate: startDate)
    }
    
    /// Update workouts for a specific week
    @discardableResult
    func updateWeekWorkouts(weekStartDate: Date, workouts: [String: String]) -> Bool {
        let weekDays = generateWeek(containing: weekStartDate)
        do {
            try workoutRepository.updateWeekWorkouts(weekDays: weekDays, workouts: workouts)
            return true
        } catch {
            print("❌ Failed to update week workouts: \(error)")
            return false
        }
    }
    
    /// Update workout for a specific date
    func updateWorkoutForDay(date: Date, workout: String) {
        do {
            try workoutRepository.updateWorkoutForDay(
                date: date,
                workout: workout,
                program: currentProgram,
                currentBlock: currentBlock
            )
        } catch {
            print("❌ Failed to update workout: \(error)")
        }
    }
    
    // MARK: - Single Workout APIs
    
    /// Plan a single workout (text-based) for a specific date
    func planSingleWorkout(for date: Date, workout: String, notes: String?, icon: String? = nil) -> Bool {
        do {
            try workoutRepository.planSingleWorkout(
                for: date,
                workout: workout,
                notes: notes,
                icon: icon,
                program: currentProgram,
                currentBlock: currentBlock
            )
            return true
        } catch {
            print("❌ Failed to plan single workout: \(error)")
            return false
        }
    }
    
    // MARK: - Structured Workout APIs
    
    /// Plan a structured workout for a specific date
    func planStructuredWorkout(for date: Date, structuredWorkout: StructuredWorkout, notes: String?, icon: String?) -> Bool {
        do {
            try workoutRepository.planStructuredWorkout(
                for: date,
                workout: structuredWorkout,
                notes: notes,
                icon: icon,
                program: currentProgram,
                currentBlock: currentBlock
            )
            return true
        } catch {
            print("❌ Failed to plan structured workout: \(error)")
            return false
        }
    }
    
    /// Update a structured workout (replace existing)
    func updateStructuredWorkout(for date: Date, structuredWorkout: StructuredWorkout, notes: String?, icon: String?) -> Bool {
        do {
            try workoutRepository.updateStructuredWorkout(
                for: date,
                workout: structuredWorkout,
                notes: notes,
                icon: icon
            )
            return true
        } catch {
            print("❌ Failed to update structured workout: \(error)")
            return false
        }
    }
    
    /// Update a single workout (replace existing)
    func updateSingleWorkout(for date: Date, workout: String, reason: String?) -> Bool {
        do {
            try workoutRepository.updateSingleWorkout(for: date, workout: workout, reason: reason)
            return true
        } catch {
            print("❌ Failed to update single workout: \(error)")
            return false
        }
    }
    
    /// Delete a single workout
    func deleteSingleWorkout(for date: Date, reason: String?) -> Bool {
        do {
            try workoutRepository.deleteWorkout(for: date)
            return true
        } catch {
            print("❌ Failed to delete workout: \(error)")
            return false
        }
    }
    
    /// Get workout day for a specific date
    func getWorkoutDay(for date: Date) -> WorkoutDay? {
        return workoutRepository.getWorkout(for: date)
    }
    
    /// Get block information for a given week number
    func getBlockForWeek(_ weekNumber: Int) -> (type: BlockType, weekInBlock: Int) {
        return blockScheduler.getBlockInfo(for: weekNumber)
    }
    
    /// Get block for a specific date
    func getBlockForDate(_ date: Date) -> TrainingBlock? {
        guard let program = currentProgram else { return nil }
        
        let blocks = blockScheduler.generateBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        return blockScheduler.getBlock(for: date, in: blocks)
    }
    
    // MARK: - Schedule Snapshot
    
    /// Generate current training block context for the coach
    func generateBlockContext() -> String {
        return snapshotBuilder.buildBlockContext(
            currentBlock: currentBlock,
            currentWeekInBlock: currentWeekInBlock,
            totalWeek: totalWeekInProgram,
            programStartDate: currentProgram?.startDate
        )
    }
    
    /// Generate a comprehensive schedule snapshot for the coach showing exercises from last 30 days with results
    func generateScheduleSnapshot() -> String {
        return snapshotBuilder.buildRecentSnapshot(endingOn: Date.current)
    }
    
}

// MARK: - DayOfWeek Extension

extension DayOfWeek {
    static func from(date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}