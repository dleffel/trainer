import Foundation

/// Manages the training schedule and calendar logic
class TrainingScheduleManager: ObservableObject {
    static let shared = TrainingScheduleManager()
    
    @Published var currentProgram: TrainingProgram?
    @Published var currentBlock: TrainingBlock?
    @Published var currentWeekInBlock: Int = 1
    @Published var workoutDays: [WorkoutDay] = []
    
    // Use new persistence layer for training program and workout days
    private let programStore: HybridCloudStore<TrainingProgram>
    private let workoutStore: HybridCloudStore<WorkoutDay>
    
    private init() {
        // Initialize hybrid cloud stores
        self.programStore = HybridCloudStore<TrainingProgram>()
        self.workoutStore = HybridCloudStore<WorkoutDay>(keyPrefix: PersistenceKey.Training.workoutPrefix)
        
        // Setup cloud change handler
        programStore.onCloudChange = { [weak self] in
            print("📱 iCloud data changed for training schedule")
            self?.loadProgram()
        }
        
        print("✅ TrainingScheduleManager initialized with HybridCloudStore (iCloud: \(programStore.useICloud))")
        loadProgram()
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
        print("🔍 DEBUG startNewProgram - Starting new program on: \(startDate)")
        let program = TrainingProgram(startDate: startDate, currentMacroCycle: 1)
        self.currentProgram = program
        saveProgram()
        updateCurrentBlock()
        
        // Debug: Print current state after initialization
        print("🔍 DEBUG startNewProgram - Current block: \(currentBlock?.type.rawValue ?? "nil")")
        print("🔍 DEBUG startNewProgram - Current week in block: \(currentWeekInBlock)")
        print("🔍 DEBUG startNewProgram - Current week overall: \(currentWeek)")
        print("🔍 DEBUG startNewProgram - Program start date: \(program.startDate)")
        
        // Workouts will be populated by the coach via plan_week_workouts
    }
    
    /// Load existing program from storage
    private func loadProgram() {
        if let program = programStore.load(forKey: PersistenceKey.Training.program) {
            self.currentProgram = program
            updateCurrentBlock()
            print("📥 Loaded program from storage")
        }
    }
    
    /// Save program to storage
    private func saveProgram() {
        guard let program = currentProgram else { return }
        
        do {
            try programStore.save(program, forKey: PersistenceKey.Training.program)
            print("💾 Saved program to storage")
        } catch {
            print("❌ Failed to save program: \(error)")
        }
    }
    
    // MARK: - Block Management
    
    /// Update the current training block based on the date
    private func updateCurrentBlock() {
        guard let program = currentProgram else {
            currentBlock = nil
            currentWeekInBlock = 1
            print("⚠️ DEBUG updateCurrentBlock - No current program")
            return
        }
        
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        let now = Date.current
        
        print("🔍 DEBUG updateCurrentBlock - Checking date: \(now)")
        print("🔍 DEBUG updateCurrentBlock - Generated \(blocks.count) blocks")
        
        // Find the current block
        for (index, block) in blocks.enumerated() {
            print("🔍 DEBUG updateCurrentBlock - Block \(index): \(block.type.rawValue) from \(block.startDate) to \(block.endDate)")
            if block.contains(date: now) {
                self.currentBlock = block
                
                // Calculate week within block
                let calendar = Calendar.current
                let weeksSinceBlockStart = calendar.dateComponents([.weekOfYear],
                                                                   from: block.startDate,
                                                                   to: now).weekOfYear ?? 0
                self.currentWeekInBlock = weeksSinceBlockStart + 1
                
                print("✅ DEBUG updateCurrentBlock - Found current block: \(block.type.rawValue)")
                print("✅ DEBUG updateCurrentBlock - Week in block: \(currentWeekInBlock)")
                break
            }
        }
        
        // Generate current week's workout days (blank, to be filled by coach)
        workoutDays = generateWeek(containing: Date.current)
    }
    
    /// Generate all training blocks for a macro-cycle
    private func generateAllBlocks(from startDate: Date, macroCycle: Int) -> [TrainingBlock] {
        print("🔍 DEBUG generateAllBlocks - Program start: \(startDate)")
        
        let calendar = Calendar.current
        // Start with Hypertrophy-Strength as per System Prompt
        let blockDurations: [(BlockType, Int)] = [
            (.hypertrophyStrength, 10),
            (.deload, 1),
            (.aerobicCapacity, 8),
            (.deload, 1)
        ]
        
        var blocks: [TrainingBlock] = []
        var currentStartDate = startDate
        
        for (blockType, duration) in blockDurations {
            let endDate = calendar.date(byAdding: .weekOfYear, value: duration, to: currentStartDate)!
            
            let block = TrainingBlock(
                type: blockType,
                startDate: currentStartDate,
                endDate: endDate,
                weekNumber: blocks.count + 1
            )
            blocks.append(block)
            print("🔍 DEBUG generateAllBlocks - Added \(blockType.rawValue) from \(currentStartDate) to \(endDate)")
            
            currentStartDate = endDate
        }
        
        return blocks
    }
    
    // MARK: - Calendar Generation
    
    /// Generate workout days for a specific week
    func generateWeek(containing date: Date) -> [WorkoutDay] {
        print("🔍 DEBUG generateWeek - Requested date: \(date)")
        print("🔍 DEBUG generateWeek - Current block: \(currentBlock?.type.rawValue ?? "nil")")
        
        // Auto-initialize program if none exists - using FIXED start date to avoid daily program creation
        if currentProgram == nil {
            print("🔄 DEBUG: currentProgram is nil during generateWeek - attempting explicit load")
            loadProgram()
            
            if currentProgram == nil {
                // Use simulated time for start date - only initialize ONCE, not daily
                let startDate = Calendar.current.startOfDay(for: Date.current)
                print("🔄 Auto-initializing training program during generateWeek with simulated start date: \(startDate)")
                startNewProgram(startDate: startDate)
            } else {
                print("✅ Found existing program after explicit load during generateWeek")
            }
        }
        
        // Find the appropriate block for the requested date, not just current block
        guard let program = currentProgram else {
            print("❌ Failed to auto-initialize program during generateWeek")
            return []
        }
        
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        var blockForDate: TrainingBlock? = nil
        
        // Find which block contains this date
        for block in blocks {
            if block.contains(date: date) {
                blockForDate = block
                break
            }
        }
        
        guard let targetBlock = blockForDate else {
            print("⚠️ DEBUG generateWeek - No block found for date \(date)")
            return []
        }
        
        print("🔍 DEBUG generateWeek - Block for requested week: \(targetBlock.type.rawValue)")
        
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        
        var days: [WorkoutDay] = []
        
        for dayOffset in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) {
                // Try to load existing workout from storage
                if let savedDay = workoutStore.load(for: dayDate) {
                    days.append(savedDay)
                    print("📥 Loaded saved workout for \(workoutStore.dateKey(for: dayDate))")
                } else {
                    // Apply workout template if available
                    let workoutDay = createWorkoutDayWithTemplate(date: dayDate, blockType: targetBlock.type)
                    days.append(workoutDay)
                    if workoutDay.isTemplateGenerated {
                        print("📝 DEBUG: Created workout day with template for \(workoutDay.dayOfWeek.name)")
                    } else {
                        print("📭 DEBUG: No template found, created blank day")
                    }
                }
            }
        }
        
        return days
    }
    
    /// Generate workout days for a specific month
    func generateMonth(containing date: Date) -> [WorkoutDay] {
        print("⚠️ DEBUG generateMonth - Called for date: \(date)")
        
        guard currentProgram != nil else { return [] }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        
        var days: [WorkoutDay] = []
        let blocks = generateAllBlocks(from: currentProgram!.startDate, macroCycle: currentProgram!.currentMacroCycle)
        
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            // Find which block this date belongs to
            if let block = blocks.first(where: { $0.contains(date: currentDate) }) {
                // Try to load saved workout data
                if let savedDay = workoutStore.load(for: currentDate) {
                    days.append(savedDay)
                    print("✅ generateMonth - Preserved saved workout with icon: \(savedDay.workoutIcon ?? "none")")
                } else {
                    // Apply workout template if available
                    let workoutDay = createWorkoutDayWithTemplate(date: currentDate, blockType: block.type)
                    days.append(workoutDay)
                    if workoutDay.isTemplateGenerated {
                        print("📝 generateMonth - Created workout day with template")
                    } else {
                        print("📭 generateMonth - Created blank workout day")
                    }
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        print("⚠️ DEBUG generateMonth - Returning \(days.count) days")
        return days
    }
    
    // MARK: - Template Application
    
    /// Create a WorkoutDay with template applied if available
    private func createWorkoutDayWithTemplate(date: Date, blockType: BlockType) -> WorkoutDay {
        let dayOfWeek = DayOfWeek.from(date: date)
        
        // Get template for this block + day combination
        guard let blockTemplate = TrainingBlockTemplate.template(for: blockType),
              let workoutTemplate = blockTemplate.templateForDay(dayOfWeek) else {
            // Fallback to blank workout day if no template available
            print("📭 No template found for \(blockType.rawValue) on \(dayOfWeek.name)")
            return WorkoutDay(date: date, blockType: blockType)
        }
        
        // Create WorkoutDay with template applied
        let workoutDay = WorkoutDay.withTemplate(date: date, blockType: blockType, template: workoutTemplate)
        print("📝 Applied template '\(workoutTemplate.title)' for \(dayOfWeek.name)")
        return workoutDay
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
        return currentProgram?.startDate
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
        startNewProgram(startDate: startDate)
    }
    
    /// Restart training program
    func restartProgram(startDate: Date = Date.current) {
        print("🧹 DEBUG restartProgram: === STARTING COMPREHENSIVE CLEAR ===")
        print("🧹 DEBUG restartProgram: Current workoutDays count: \(workoutDays.count)")
        
        // Clear old program data
        currentProgram = nil
        workoutDays = []
        
        print("🧹 DEBUG restartProgram: In-memory data cleared")
        
        // Clear program using new persistence layer
        do {
            try programStore.delete(forKey: PersistenceKey.Training.program)
            print("🧹 DEBUG restartProgram: Cleared program")
        } catch {
            print("⚠️ Failed to clear program: \(error)")
        }
        
        // Clear workout days using clearRange
        let calendar = Calendar.current
        let startClearDate = calendar.date(byAdding: .year, value: -1, to: Date.current)!
        let endClearDate = calendar.date(byAdding: .year, value: 1, to: Date.current)!
        
        do {
            try workoutStore.clearRange(from: startClearDate, to: endClearDate)
            print("🧹 DEBUG restartProgram: Cleared workout days")
        } catch {
            print("⚠️ Failed to clear workout days: \(error)")
        }
        
        // Clear results using WorkoutResultsManager
        WorkoutResultsManager.shared.clearResults(from: startClearDate, to: endClearDate)
        print("🧹 DEBUG restartProgram: Cleared workout results")
        
        print("🧹 DEBUG restartProgram: === CLEAR COMPLETE, STARTING NEW PROGRAM ===")
        
        // Start fresh program
        startNewProgram(startDate: startDate)
    }
    
    /// Update workouts for a specific week
    @discardableResult
    func updateWeekWorkouts(weekStartDate: Date, workouts: [String: String]) -> Bool {
        let weekDays = generateWeek(containing: weekStartDate)
        return processWorkoutsForDays(weekDays, workouts: workouts)
    }
    
    private func processWorkoutsForDays(_ weekDays: [WorkoutDay], workouts: [String: String]) -> Bool {
        var success = true
        
        for (dayName, workoutText) in workouts {
            // Find matching day by comparing lowercase names
            if let workoutDay = weekDays.first(where: { $0.dayOfWeek.name.lowercased() == dayName.lowercased() }) {
                var updatedDay = workoutDay
                updatedDay.plannedWorkout = workoutText
                updatedDay.isCoachPlanned = true
                
                if !saveWorkoutDay(updatedDay) {
                    success = false
                }
            }
        }
        
        return success
    }
    
    /// Update workout for a specific date
    func updateWorkoutForDay(date: Date, workout: String) {
        if let workoutDay = getWorkoutDay(for: date) {
            var updatedDay = workoutDay
            updatedDay.plannedWorkout = workout
            updatedDay.isCoachPlanned = true
            _ = saveWorkoutDay(updatedDay)
        } else {
            var newDay = generateDayForDate(date)
            newDay.plannedWorkout = workout
            newDay.isCoachPlanned = true
            workoutDays.append(newDay)
            _ = saveWorkoutDay(newDay)
        }
    }
    
    /// Generate a workout day for a specific date
    private func generateDayForDate(_ date: Date) -> WorkoutDay {
        guard currentProgram != nil else {
            return WorkoutDay(date: date, blockType: .hypertrophyStrength)
        }
        
        let blocks = generateAllBlocks(from: currentProgram!.startDate, macroCycle: currentProgram!.currentMacroCycle)
        let blockForDate = blocks.first(where: { $0.contains(date: date) })
        
        let targetBlock = blockForDate ?? currentBlock ?? TrainingBlock(
            type: .hypertrophyStrength,
            startDate: date,
            endDate: date,
            weekNumber: 1
        )
        
        return createWorkoutDayWithTemplate(date: date, blockType: targetBlock.type)
    }
    
    // MARK: - Single Workout APIs
    
    /// Plan a single workout (text-based) for a specific date
    func planSingleWorkout(for date: Date, workout: String, notes: String?, icon: String? = nil) -> Bool {
        print("📝 Planning single workout for \(date)")
        if let icon = icon {
            print("   with icon: \(icon)")
        }
        
        // Find or create workout day
        if let existingDay = getWorkoutDay(for: date) {
            // Update existing
            var updatedDay = existingDay
            // Store notes as part of workout text if provided
            if let notes = notes {
                updatedDay.plannedWorkout = "\(workout)\n\n📝 Notes: \(notes)"
            } else {
                updatedDay.plannedWorkout = workout
            }
            updatedDay.isCoachPlanned = true
            updatedDay.workoutIcon = icon  // Store the coach-selected icon
            
            // Save to storage
            return saveWorkoutDay(updatedDay)
        } else {
            // Create new workout day
            var newDay = generateDayForDate(date)
            // Store notes as part of workout text if provided
            if let notes = notes {
                newDay.plannedWorkout = "\(workout)\n\n📝 Notes: \(notes)"
            } else {
                newDay.plannedWorkout = workout
            }
            newDay.isCoachPlanned = true
            newDay.workoutIcon = icon  // Store the coach-selected icon
            
            // Add to workoutDays array
            workoutDays.append(newDay)
            
            // Save to storage
            return saveWorkoutDay(newDay)
        }
    }
    
    // MARK: - Structured Workout APIs
    
    /// Plan a structured workout for a specific date
    func planStructuredWorkout(for date: Date, structuredWorkout: StructuredWorkout, notes: String?, icon: String?) -> Bool {
        print("🔍 DEBUG planStructuredWorkout: === STARTING ===")
        print("🔍 DEBUG planStructuredWorkout: Date = \(date)")
        print("🔍 DEBUG planStructuredWorkout: Workout title = '\(String(describing: structuredWorkout.title))'")
        print("🔍 DEBUG planStructuredWorkout: Exercise count = \(structuredWorkout.exercises.count)")
        let distribution = structuredWorkout.exerciseDistribution
        print("🔍 DEBUG planStructuredWorkout: Distribution = cardio:\(distribution.cardio) strength:\(distribution.strength) mobility:\(distribution.mobility) yoga:\(distribution.yoga) generic:\(distribution.generic)")
        print("🔍 DEBUG planStructuredWorkout: Notes = \(notes ?? "nil")")
        print("🔍 DEBUG planStructuredWorkout: Icon = \(icon ?? "nil")")
        print("🔍 DEBUG planStructuredWorkout: Current workoutDays count = \(workoutDays.count)")
        
        // Find or create workout day
        if let existingDay = getWorkoutDay(for: date) {
            print("🔍 DEBUG planStructuredWorkout: Found existing day, updating")
            // Update existing
            var updatedDay = existingDay
            updatedDay.structuredWorkout = structuredWorkout
            updatedDay.isCoachPlanned = true
            updatedDay.workoutIcon = icon
            // Do NOT write to plannedWorkout - structured workouts only
            
            // Set notes separately if provided
            if let notes = notes {
                print("🔍 DEBUG planStructuredWorkout: Setting notes: \(notes)")
            }
            
            print("🔍 DEBUG planStructuredWorkout: Calling saveWorkoutDay() for existing day")
            // Save to storage
            let saveResult = saveWorkoutDay(updatedDay)
            print("🔍 DEBUG planStructuredWorkout: Save result = \(saveResult)")
            return saveResult
        } else {
            print("🔍 DEBUG planStructuredWorkout: No existing day found, creating new")
            // Create new workout day
            var newDay = generateDayForDate(date)
            print("🔍 DEBUG planStructuredWorkout: Generated new day for \(date)")
            newDay.structuredWorkout = structuredWorkout
            newDay.isCoachPlanned = true
            newDay.workoutIcon = icon
            // Do NOT write to plannedWorkout - structured workouts only
            
            if let notes = notes {
                print("🔍 DEBUG planStructuredWorkout: Setting notes: \(notes)")
            }
            
            // Add to workoutDays array
            workoutDays.append(newDay)
            print("🔍 DEBUG planStructuredWorkout: Added to workoutDays array, new count = \(workoutDays.count)")
            
            print("🔍 DEBUG planStructuredWorkout: Calling saveWorkoutDay() for new day")
            // Save to storage
            let saveResult = saveWorkoutDay(newDay)
            print("🔍 DEBUG planStructuredWorkout: Save result = \(saveResult)")
            print("✅ DEBUG planStructuredWorkout: COMPLETED")
            return saveResult
        }
    }
    
    /// Update a structured workout (replace existing)
    func updateStructuredWorkout(for date: Date, structuredWorkout: StructuredWorkout, notes: String?, icon: String?) -> Bool {
        if let existingDay = getWorkoutDay(for: date) {
            var updatedDay = existingDay
            updatedDay.structuredWorkout = structuredWorkout
            updatedDay.workoutIcon = icon
            // Notes are not stored in this method
            return saveWorkoutDay(updatedDay)
        }
        return false
    }
    
    /// Update a single workout (replace existing)
    func updateSingleWorkout(for date: Date, workout: String, reason: String?) -> Bool {
        if let existingDay = getWorkoutDay(for: date) {
            var updatedDay = existingDay
            updatedDay.plannedWorkout = workout
            return saveWorkoutDay(updatedDay)
        }
        return false
    }
    
    /// Delete a single workout
    func deleteSingleWorkout(for date: Date, reason: String?) -> Bool {
        do {
            try workoutStore.delete(for: date)
            print("🗑️ Deleted workout for \(workoutStore.dateKey(for: date))")
            return true
        } catch {
            print("❌ Failed to delete workout: \(error)")
            return false
        }
    }
    
    /// Get workout day for a specific date
    func getWorkoutDay(for date: Date) -> WorkoutDay? {
        return workoutStore.load(for: date)
    }
    
    /// Save a workout day
    private func saveWorkoutDay(_ workoutDay: WorkoutDay) -> Bool {
        do {
            try workoutStore.save(workoutDay, for: workoutDay.date)
            print("💾 Saved workout day for \(workoutStore.dateKey(for: workoutDay.date))")
            return true
        } catch {
            print("❌ Failed to save workout day: \(error)")
            return false
        }
    }
    
    /// Get block information for a given week number
    func getBlockForWeek(_ weekNumber: Int) -> (type: BlockType, weekInBlock: Int) {
        if weekNumber <= 8 {
            return (.hypertrophyStrength, weekNumber)
        } else if weekNumber == 9 {
            return (.deload, 1)
        } else if weekNumber <= 18 {
            return (.aerobicCapacity, weekNumber - 9)
        } else {
            return (.deload, 1)
        }
    }
    
    /// Get block for a specific date
    func getBlockForDate(_ date: Date) -> TrainingBlock? {
        guard let program = currentProgram else { return nil }
        
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        return blocks.first(where: { $0.contains(date: date) })
    }
    
    // MARK: - Schedule Snapshot
    
    /// Generate a comprehensive schedule snapshot for the coach
    /// Note: Extended implementation is in TrainingScheduleManager+Snapshot.swift
    func generateScheduleSnapshot() -> String {
        // This will be extended by the snapshot file
        return "Schedule snapshot not yet implemented"
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