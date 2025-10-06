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
        
        print("🔍 DIAGNOSTIC generateWeek - Program start date: \(program.startDate)")
        
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        
        var days: [WorkoutDay] = []
        
        for dayOffset in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) {
                let dateKey = workoutStore.dateKey(for: dayDate)
                print("🔍 DIAGNOSTIC generateWeek - Processing day \(dayOffset): \(dateKey)")
                
                // Check if this date is before the program starts
                if dayDate < program.startDate {
                    print("📭 DIAGNOSTIC generateWeek - Date \(dateKey) is BEFORE program start, creating pre-program rest day")
                    // Create a pre-program rest day (no workout)
                    let preProgram = WorkoutDay(date: dayDate, blockType: .hypertrophyStrength)
                    days.append(preProgram)
                    continue
                }
                
                // Find which block contains this date
                guard let block = blocks.first(where: { $0.contains(date: dayDate) }) else {
                    print("⚠️ DIAGNOSTIC generateWeek - No block found for \(dateKey), creating blank day")
                    let blankDay = WorkoutDay(date: dayDate, blockType: .hypertrophyStrength)
                    days.append(blankDay)
                    continue
                }
                
                // Try to load existing workout from storage
                if let savedDay = workoutStore.load(for: dayDate) {
                    days.append(savedDay)
                    print("✅ DIAGNOSTIC generateWeek - Loaded saved workout for \(dateKey) with icon: \(savedDay.workoutIcon ?? "none"), hasWorkout: \(savedDay.hasWorkout)")
                } else {
                    // Create blank workout day for this block
                    let workoutDay = WorkoutDay(date: dayDate, blockType: block.type)
                    days.append(workoutDay)
                    print("📭 DIAGNOSTIC generateWeek - Created blank workout day for \(workoutDay.dayOfWeek.name) in \(block.type.rawValue)")
                }
            }
        }
        
        print("🔍 DIAGNOSTIC generateWeek - Returning \(days.count) days total")
        
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
                    // Create blank workout day
                    let workoutDay = WorkoutDay(date: currentDate, blockType: block.type)
                    days.append(workoutDay)
                    print("📭 generateMonth - Created blank workout day")
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        print("⚠️ DEBUG generateMonth - Returning \(days.count) days")
        return days
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
        
        return WorkoutDay(date: date, blockType: targetBlock.type)
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
    
    /// Generate current training block context for the coach
    func generateBlockContext() -> String {
        guard let block = currentBlock, let program = currentProgram else {
            return "## CURRENT TRAINING BLOCK\n\nNo active training program.\n"
        }
        
        var context = "## CURRENT TRAINING BLOCK\n\n"
        
        // PURE STATE ONLY - no interpretation or guidance
        context += "**Block Type**: \(block.type.rawValue)\n"
        context += "**Week in Block**: \(currentWeekInBlock) of \(block.type.duration)\n"
        context += "**Total Week in Program**: \(totalWeekInProgram) of 20\n"
        context += "**Program Started**: \(formatDate(program.startDate))\n"
        
        return context
    }
    
    /// Generate a comprehensive schedule snapshot for the coach showing exercises from last 30 days with results
    func generateScheduleSnapshot() -> String {
        let calendar = Calendar.current
        let today = Date.current  // Use Date.current for simulated time support
        
        // Calculate 30 days ago
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else {
            return "Unable to calculate date range for schedule snapshot"
        }
        
        // Start building the snapshot
        var snapshot = "## SCHEDULE SNAPSHOT (Last 30 Days)\n"
        snapshot += "Generated: \(formatDateTime(today))\n\n"
        
        // Iterate through each date from 30 days ago to today
        var currentDate = thirtyDaysAgo
        var daysProcessed = 0
        
        while currentDate <= today {
            // Load workout for this date
            if let workoutDay = workoutStore.load(for: currentDate) {
                // Load results for this date
                let results = loadSetResults(for: currentDate)
                
                // Format this day's entry
                let dayEntry = formatDayEntry(workoutDay: workoutDay, results: results)
                if !dayEntry.isEmpty {
                    snapshot += dayEntry
                    daysProcessed += 1
                }
            }
            
            // Move to next day
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        if daysProcessed == 0 {
            snapshot += "No workouts scheduled or completed in this period.\n"
        }
        
        return snapshot
    }
    
    // MARK: - Snapshot Helper Methods
    
    /// Format a single day's entry with workout and results
    private func formatDayEntry(workoutDay: WorkoutDay, results: [WorkoutSetResult]) -> String {
        var entry = ""
        
        // Only show days that have a workout
        guard workoutDay.hasWorkout else {
            return entry
        }
        
        // Date header
        entry += "### \(formatDate(workoutDay.date)) - \(workoutDay.dayOfWeek.name)\n"
        
        // Check if we have structured workout
        if let workout = workoutDay.structuredWorkout {
            entry += "**Scheduled Exercises:**\n"
            
            for (index, exercise) in workout.exercises.enumerated() {
                entry += "\(index + 1). \(formatExerciseName(exercise))\n"
                entry += "   - Planned: \(formatExerciseDetails(exercise))\n"
                
                // Match and format results for this exercise
                let exerciseResults = matchResultsToExercise(exerciseName: formatExerciseName(exercise), results: results)
                if !exerciseResults.isEmpty {
                    entry += "   - Results:\n"
                    entry += formatResultsForExercise(exerciseResults)
                } else {
                    entry += "   - Results: Not yet logged\n"
                }
                entry += "\n"
            }
        } else if let legacyWorkout = workoutDay.plannedWorkout {
            // Legacy workout format
            entry += "**Workout:** \(legacyWorkout)\n"
            if !results.isEmpty {
                entry += "**Results:**\n"
                entry += formatAllResults(results)
            }
            entry += "\n"
        }
        
        return entry
    }
    
    /// Format exercise name from Exercise object
    private func formatExerciseName(_ exercise: Exercise) -> String {
        if let name = exercise.name, !name.isEmpty {
            return name
        }
        
        // Fallback to kind with cleaned up formatting
        let cleanKind = exercise.kind
            .replacingOccurrences(of: "cardio", with: "Cardio - ", options: .caseInsensitive)
            .replacingOccurrences(of: "strength", with: "Strength")
        return cleanKind.isEmpty ? "Exercise" : cleanKind
    }
    
    /// Format exercise details based on type
    private func formatExerciseDetails(_ exercise: Exercise) -> String {
        switch exercise.detail {
        case .strength(let detail):
            return formatStrengthDetails(detail)
        case .cardio(let detail):
            return formatCardioDetails(detail)
        case .mobility(let detail):
            return formatMobilityDetails(detail)
        case .yoga(let detail):
            return formatYogaDetails(detail)
        case .generic(let detail):
            return formatGenericDetails(detail)
        }
    }
    
    /// Format strength exercise details
    private func formatStrengthDetails(_ detail: StrengthDetail) -> String {
        var parts: [String] = []
        
        if let movement = detail.movement {
            parts.append(movement)
        }
        
        if let sets = detail.sets, !sets.isEmpty {
            parts.append("\(sets.count) sets")
            
            // Show rep scheme if consistent
            let reps = sets.compactMap { $0.reps?.displayValue }
            if !reps.isEmpty {
                let uniqueReps = Set(reps)
                if uniqueReps.count == 1, let rep = uniqueReps.first {
                    parts.append("\(rep) reps")
                } else {
                    parts.append("varied reps")
                }
            }
            
            // Show weight if specified
            if let weight = sets.first?.weight {
                parts.append("@ \(weight)")
            }
            
            // Show tempo if specified
            if let tempo = sets.first?.tempo {
                parts.append("tempo: \(tempo)")
            }
        }
        
        if let superset = detail.superset {
            parts.append("(superset: \(superset))")
        }
        
        return parts.joined(separator: ", ")
    }
    
    /// Format cardio exercise details
    private func formatCardioDetails(_ detail: CardioDetail) -> String {
        var parts: [String] = []
        
        if let modality = detail.modality {
            parts.append(modality)
        }
        
        if let total = detail.total ?? detail.effectiveTotal {
            if let duration = total.durationMinutes {
                parts.append("\(duration) min")
            }
            if let distance = total.distanceMeters {
                parts.append("\(distance)m")
            }
        }
        
        if let segments = detail.segments, !segments.isEmpty {
            parts.append("\(segments.count) intervals")
        }
        
        return parts.isEmpty ? "Cardio workout" : parts.joined(separator: ", ")
    }
    
    /// Format mobility exercise details
    private func formatMobilityDetails(_ detail: MobilityDetail) -> String {
        guard let blocks = detail.blocks, !blocks.isEmpty else {
            return "Mobility work"
        }
        
        let blockNames = blocks.map { $0.name }.joined(separator: ", ")
        return "\(blocks.count) movements: \(blockNames)"
    }
    
    /// Format yoga exercise details
    private func formatYogaDetails(_ detail: YogaDetail) -> String {
        guard let blocks = detail.blocks, !blocks.isEmpty else {
            return "Yoga session"
        }
        
        let totalMinutes = blocks.compactMap { $0.durationMinutes }.reduce(0, +)
        return "\(blocks.count) segments, \(totalMinutes) min total"
    }
    
    /// Format generic exercise details
    private func formatGenericDetails(_ detail: GenericDetail) -> String {
        var parts: [String] = []
        
        if let items = detail.items, !items.isEmpty {
            parts.append(items.joined(separator: ", "))
        }
        
        if let notes = detail.notes {
            parts.append(notes)
        }
        
        return parts.isEmpty ? "Workout" : parts.joined(separator: " - ")
    }
    
    /// Match results to a specific exercise by name (case-insensitive)
    private func matchResultsToExercise(exerciseName: String, results: [WorkoutSetResult]) -> [WorkoutSetResult] {
        let cleanName = exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return results.filter { result in
            let resultName = result.exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return resultName == cleanName || resultName.contains(cleanName) || cleanName.contains(resultName)
        }
    }
    
    /// Format results for a specific exercise, grouped by set
    private func formatResultsForExercise(_ results: [WorkoutSetResult]) -> String {
        // Sort by set number, then by timestamp
        let sortedResults = results.sorted { r1, r2 in
            if let s1 = r1.setNumber, let s2 = r2.setNumber {
                return s1 < s2
            }
            return r1.timestamp < r2.timestamp
        }
        
        var formatted = ""
        for result in sortedResults {
            formatted += "     * "
            
            if let setNum = result.setNumber {
                formatted += "Set \(setNum): "
            }
            
            var parts: [String] = []
            
            if let reps = result.reps {
                parts.append("\(reps) reps")
            }
            
            if let loadLb = result.loadLb {
                parts.append("@ \(loadLb) lb")
            } else if let loadKg = result.loadKg {
                parts.append("@ \(loadKg) kg")
            }
            
            if let rir = result.rir {
                parts.append("RIR: \(rir)")
            }
            
            if let rpe = result.rpe {
                parts.append("RPE: \(rpe)")
            }
            
            formatted += parts.joined(separator: ", ")
            
            if let notes = result.notes, !notes.isEmpty {
                formatted += " - \(notes)"
            }
            
            formatted += "\n"
        }
        
        return formatted
    }
    
    /// Format all results without exercise grouping (for legacy workouts)
    private func formatAllResults(_ results: [WorkoutSetResult]) -> String {
        let sortedResults = results.sorted { $0.timestamp < $1.timestamp }
        
        var formatted = ""
        for result in sortedResults {
            formatted += "  - \(result.exerciseName): "
            
            var parts: [String] = []
            
            if let setNum = result.setNumber {
                parts.append("Set \(setNum)")
            }
            
            if let reps = result.reps {
                parts.append("\(reps) reps")
            }
            
            if let loadLb = result.loadLb {
                parts.append("@ \(loadLb) lb")
            } else if let loadKg = result.loadKg {
                parts.append("@ \(loadKg) kg")
            }
            
            if let rir = result.rir {
                parts.append("RIR: \(rir)")
            }
            
            if let rpe = result.rpe {
                parts.append("RPE: \(rpe)")
            }
            
            formatted += parts.joined(separator: ", ")
            formatted += "\n"
        }
        
        return formatted
    }
    
    /// Format date for display (e.g., "Oct 5, 2025")
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")  // Required per .roorules
        return formatter.string(from: date)
    }
    
    /// Format date and time for display (e.g., "Oct 5, 2025 at 2:57 PM")
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        formatter.timeZone = TimeZone.current  // Use local time for display
        return formatter.string(from: date)
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