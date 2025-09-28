import Foundation

/// Manages the training schedule and calendar logic
class TrainingScheduleManager: ObservableObject {
    static let shared = TrainingScheduleManager()
    
    @Published var currentProgram: TrainingProgram?
    @Published var currentBlock: TrainingBlock?
    @Published var currentWeekInBlock: Int = 1
    @Published var workoutDays: [WorkoutDay] = []
    
    private let userDefaults = UserDefaults.standard
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let programKey = "TrainingProgram"
    private var useICloud = true
    
    private init() {
        setupICloudSync()
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
    
    // MARK: - iCloud Setup
    
    private func setupICloudSync() {
        // Check if iCloud is available
        if FileManager.default.ubiquityIdentityToken != nil {
            print("✅ iCloud available for TrainingScheduleManager")
            useICloud = true
            
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
            print("⚠️ iCloud not available for TrainingScheduleManager")
            useICloud = false
        }
    }
    
    @objc private func handleICloudChange(_ notification: Notification) {
        print("📱 iCloud data changed for training schedule")
        loadProgram()
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
        var data: Data?
        
        // Try iCloud first if available
        if useICloud {
            data = iCloudStore.data(forKey: programKey)
            if data != nil {
                print("📥 Loaded program from iCloud")
            }
        }
        
        // Fall back to local storage
        if data == nil {
            data = userDefaults.data(forKey: programKey)
            if data != nil {
                print("📥 Loaded program from local storage")
            }
        }
        
        if let data = data,
           let program = try? JSONDecoder().decode(TrainingProgram.self, from: data) {
            self.currentProgram = program
            updateCurrentBlock()
        }
    }
    
    /// Save program to storage
    private func saveProgram() {
        guard let program = currentProgram else { return }
        
        if let data = try? JSONEncoder().encode(program) {
            // Save to local storage
            userDefaults.set(data, forKey: programKey)
            
            // Save to iCloud if available
            if useICloud {
                iCloudStore.set(data, forKey: programKey)
                iCloudStore.synchronize()
                print("☁️ Saved program to iCloud")
            } else {
                print("💾 Saved program to local storage")
            }
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
                // Check if we have a saved workout for this date first
                let key = "workout_\(dateKey(for: dayDate))"
                var workoutDay: WorkoutDay
                
                // DEBUG: Enhanced logging for workout loading
                print("🔍 DEBUG: Looking for workout with key: \(key)")
                print("🔍 DEBUG: Date being checked: \(dayDate)")
                print("🔍 DEBUG: Using iCloud: \(useICloud)")
                
                // Check both storage locations for debugging
                let iCloudData = iCloudStore.data(forKey: key)
                let localData = userDefaults.data(forKey: key)
                
                print("🔍 DEBUG: Data in iCloud: \(iCloudData != nil ? "YES (\(iCloudData!.count) bytes)" : "NO")")
                print("🔍 DEBUG: Data in UserDefaults: \(localData != nil ? "YES (\(localData!.count) bytes)" : "NO")")
                
                // Try to load existing workout from storage
                if let data = useICloud ? iCloudData : localData,
                   let savedDay = try? JSONDecoder().decode(WorkoutDay.self, from: data) {
                    workoutDay = savedDay
                    print("📥 Loaded saved workout for \(dateKey(for: dayDate))")
                    print("📥 DEBUG: Planned workout content: \(savedDay.plannedWorkout ?? "nil")")
                    print("🔍 DEBUG: StructuredWorkout exists: \(savedDay.structuredWorkout != nil)")
                    if let structuredWorkout = savedDay.structuredWorkout {
                        print("🔍 DEBUG: StructuredWorkout title: '\(String(describing: structuredWorkout.title))'")
                        print("🔍 DEBUG: StructuredWorkout exercise count: \(structuredWorkout.exercises.count)")
                    }
                } else {
                    // NEW: Apply workout template if available
                    workoutDay = createWorkoutDayWithTemplate(date: dayDate, blockType: targetBlock.type)
                    if workoutDay.isTemplateGenerated {
                        print("📝 DEBUG: Created workout day with template for \(workoutDay.dayOfWeek.name)")
                        print("🔍 DEBUG: Template type: \(workoutDay.templateType?.rawValue ?? "unknown")")
                    } else {
                        print("📭 DEBUG: No template found, created blank day")
                    }
                }
                
                days.append(workoutDay)
            }
        }
        
        return days
    }
    
    /// Generate workout days for a specific month
    func generateMonth(containing date: Date) -> [WorkoutDay] {
        print("⚠️ DEBUG generateMonth - Called for date: \(date)")
        print("⚠️ DEBUG generateMonth - This function creates NEW WorkoutDay objects without preserving saved data!")
        
        guard currentProgram != nil else { return [] }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        
        var days: [WorkoutDay] = []
        let blocks = generateAllBlocks(from: currentProgram!.startDate, macroCycle: currentProgram!.currentMacroCycle)
        
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            // Find which block this date belongs to
            if let block = blocks.first(where: { $0.contains(date: currentDate) }) {
                // BUG: This creates a NEW WorkoutDay without checking for saved data
                let key = "workout_\(dateKey(for: currentDate))"
                
                // Check if we have saved workout data
                if let data = useICloud ? iCloudStore.data(forKey: key) : userDefaults.data(forKey: key),
                   let savedDay = try? JSONDecoder().decode(WorkoutDay.self, from: data) {
                    // Use the saved workout (preserves icon and other custom data)
                    days.append(savedDay)
                    print("✅ generateMonth - Preserved saved workout with icon: \(savedDay.workoutIcon ?? "none")")
                } else {
                    // NEW: Apply workout template if available
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
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")  // Force UTC to ensure consistency
        let key = formatter.string(from: date)
        
        // DEBUG: Log timezone information
        print("🔑 DEBUG dateKey - Input date: \(date)")
        print("🔑 DEBUG dateKey - Generated key: \(key)")
        print("🔑 DEBUG dateKey - System timezone: \(TimeZone.current.identifier)")
        
        return key
    }
    
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
        
        // Clear completion data with extended range
        if useICloud {
            print("🧹 DEBUG restartProgram: Clearing iCloud data...")
            iCloudStore.removeObject(forKey: programKey)
            
            // Extended clearing range to catch more data
            var clearedKeys: [String] = []
            for i in -365...365 {
                if let date = Calendar.current.date(byAdding: .day, value: i, to: Date.current) {
                    let workoutKey = "workout_\(dateKey(for: date))"
                    iCloudStore.removeObject(forKey: workoutKey)
                    clearedKeys.append(workoutKey)
                    
                    // Clear results using WorkoutResultsManager
                    WorkoutResultsManager.shared.clearResults(from: date, to: date)
                }
            }
            print("🧹 DEBUG restartProgram: Cleared \(clearedKeys.count) iCloud keys")
            iCloudStore.synchronize()
        }
        
        // Clear local storage with extended range
        print("🧹 DEBUG restartProgram: Clearing UserDefaults data...")
        userDefaults.removeObject(forKey: programKey)
        
        var clearedLocalKeys: [String] = []
        for i in -365...365 {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: Date.current) {
                let workoutKey = "workout_\(dateKey(for: date))"
                userDefaults.removeObject(forKey: workoutKey)
                clearedLocalKeys.append(workoutKey)
                
                // Results clearing is handled by WorkoutResultsManager above
            }
        }
        print("🧹 DEBUG restartProgram: Cleared \(clearedLocalKeys.count) UserDefaults keys")
        
        print("🧹 DEBUG restartProgram: === CLEAR COMPLETE, STARTING NEW PROGRAM ===")
        
        // Start fresh program
        startNewProgram(startDate: startDate)
        
        print("🧹 DEBUG restartProgram: New program started with \(workoutDays.count) workout days")
        print("🧹 DEBUG restartProgram: === RESTART COMPLETE ===")
    }
    
    /// Update workouts for a specific week
    func updateWeekWorkouts(weekStartDate: Date, workouts: [String: String]) -> Bool {
        guard let program = currentProgram else {
            print("⚠️ No active program to update workouts")
            return false
        }
        
        print("📝 updateWeekWorkouts - Starting date: \(weekStartDate)")
        print("📝 updateWeekWorkouts - Workouts to save: \(workouts.count)")
        
        // Check if date is before program start - use current week instead
        var adjustedDate = weekStartDate
        if weekStartDate < program.startDate {
            print("⚠️ Date \(weekStartDate) is before program start \(program.startDate)")
            print("📝 Using current week instead")
            adjustedDate = Date.current
        }
        
        // Get all days for this week
        let weekDays = generateWeek(containing: adjustedDate)
        print("📝 updateWeekWorkouts - Generated \(weekDays.count) days for the week")
        
        // If still no days generated, try the first week of the program
        if weekDays.isEmpty {
            print("📝 Falling back to first week of program")
            let weekDays = generateWeek(containing: program.startDate)
            if !weekDays.isEmpty {
                return processWorkoutsForDays(weekDays, workouts: workouts)
            }
        }
        
        return processWorkoutsForDays(weekDays, workouts: workouts)
    }
    
    private func processWorkoutsForDays(_ weekDays: [WorkoutDay], workouts: [String: String]) -> Bool {
        for day in weekDays {
            let dayName = day.dayOfWeek.name.lowercased()
            print("📝 Processing \(dayName), date: \(day.date)")
            
            if let workout = workouts[dayName] {
                print("📝 Found workout for \(dayName): \(workout.prefix(50))...")
                // Update the workout for this day
                updateWorkoutForDay(date: day.date, workout: workout)
            } else {
                print("⚠️ No workout provided for \(dayName)")
            }
        }
        
        return true
    }
    
    /// Update workout for a specific day
    func updateWorkoutForDay(date: Date, workout: String) {
        print("💾 updateWorkoutForDay - Date: \(date), Workout: \(workout.prefix(30))...")
        
        // Find the workout day in our current days
        if let index = workoutDays.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            print("💾 Found existing day at index \(index)")
            workoutDays[index].plannedWorkout = workout
            
            // Save to persistent storage
            let key = "workout_\(dateKey(for: date))"
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(workoutDays[index]) {
                if useICloud {
                    iCloudStore.set(data, forKey: key)
                    iCloudStore.synchronize()
                    print("☁️ Saved to iCloud with key: \(key)")
                }
                userDefaults.set(data, forKey: key)
                print("💾 Saved to UserDefaults with key: \(key)")
            } else {
                print("❌ Failed to encode workout day")
            }
        } else {
            print("💾 Creating new workout day for date")
            // Create a new workout day for this date
            var newDay = generateDayForDate(date)
            newDay.plannedWorkout = workout
            
            // Save to persistent storage
            let key = "workout_\(dateKey(for: date))"
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(newDay) {
                if useICloud {
                    iCloudStore.set(data, forKey: key)
                    iCloudStore.synchronize()
                    print("☁️ Saved new day to iCloud with key: \(key)")
                }
                userDefaults.set(data, forKey: key)
                userDefaults.synchronize() // Force sync
                print("💾 Saved new day to UserDefaults with key: \(key)")
                
                // Verify the save
                if let verifyData = userDefaults.data(forKey: key) {
                    print("✅ Verified: Data exists in UserDefaults for key: \(key) (\(verifyData.count) bytes)")
                } else {
                    print("❌ ERROR: Data NOT found in UserDefaults immediately after save for key: \(key)")
                }
            } else {
                print("❌ Failed to encode new workout day")
            }
        }
    }
    
    /// Generate a workout day for a specific date
    private func generateDayForDate(_ date: Date) -> WorkoutDay {
        // Find which block this date belongs to
        let blocks = generateAllBlocks(from: currentProgram!.startDate, macroCycle: currentProgram!.currentMacroCycle)
        var blockForDate: TrainingBlock? = nil
        
        for block in blocks {
            if block.contains(date: date) {
                blockForDate = block
                break
            }
        }
        
        let targetBlock = blockForDate ?? currentBlock ?? TrainingBlock(
            type: .aerobicCapacity,
            startDate: date,
            endDate: date,
            weekNumber: 1
        )
        
        return WorkoutDay(date: date, blockType: targetBlock.type)
    }
    
    
    // MARK: - New Single-Day CRUD Operations for Adaptive Planning
    
    /// Plan a single workout for a specific date (LEGACY - for text workouts)
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
    
    /// Update an existing structured workout
    func updateStructuredWorkout(for date: Date, structuredWorkout: StructuredWorkout, notes: String?, icon: String?) -> Bool {
        print("✏️ Updating structured workout for \(date)")
        
        guard var workoutDay = getWorkoutDay(for: date) else {
            print("❌ No workout found to update")
            return false
        }
        
        // Update the structured workout
        workoutDay.structuredWorkout = structuredWorkout
        workoutDay.isCoachPlanned = true
        workoutDay.workoutIcon = icon
        // Do NOT write to plannedWorkout - structured workouts only
        
        if let notes = notes {
            print("   Notes: \(notes)")
        }
        
        return saveWorkoutDay(workoutDay)
    }
    
    /// Update an existing workout with modification tracking
    func updateSingleWorkout(for date: Date, workout: String, reason: String?) -> Bool {
        print("✏️ Updating workout for \(date)")
        
        guard var workoutDay = getWorkoutDay(for: date) else {
            print("❌ No workout found to update")
            return false
        }
        
        // Update the workout with modification reason embedded
        if let reason = reason {
            workoutDay.plannedWorkout = "\(workout)\n\n✏️ Modified: \(reason)"
        } else {
            workoutDay.plannedWorkout = workout
        }
        workoutDay.isCoachPlanned = true
        
        return saveWorkoutDay(workoutDay)
    }
    
    /// Delete a workout (set to rest day)
    func deleteSingleWorkout(for date: Date, reason: String?) -> Bool {
        print("🗑️ Deleting workout for \(date)")
        
        guard var workoutDay = getWorkoutDay(for: date) else {
            print("❌ No workout found to delete")
            return false
        }
        
        // Clear the workout and add reason if provided
        if let reason = reason {
            workoutDay.plannedWorkout = "Rest day - \(reason)"
        } else {
            workoutDay.plannedWorkout = nil
        }
        
        return saveWorkoutDay(workoutDay)
    }
    
    /// Get a specific day's workout
    func getWorkoutDay(for date: Date) -> WorkoutDay? {
        // First check in-memory workoutDays
        if let day = workoutDays.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            return day
        }
        
        // Then check persistent storage
        let key = "workout_\(dateKey(for: date))"
        var data: Data?
        
        if useICloud {
            data = iCloudStore.data(forKey: key)
        }
        
        if data == nil {
            data = userDefaults.data(forKey: key)
        }
        
        if let data = data,
           let workoutDay = try? JSONDecoder().decode(WorkoutDay.self, from: data) {
            return workoutDay
        }
        
        return nil
    }
    
    /// Save a workout day to persistent storage
    private func saveWorkoutDay(_ workoutDay: WorkoutDay) -> Bool {
        let key = "workout_\(dateKey(for: workoutDay.date))"
        let encoder = JSONEncoder()
        
        guard let data = try? encoder.encode(workoutDay) else {
            print("❌ Failed to encode workout day")
            return false
        }
        
        // Update in-memory array
        if let index = workoutDays.firstIndex(where: {
            Calendar.current.isDate($0.date, inSameDayAs: workoutDay.date)
        }) {
            workoutDays[index] = workoutDay
        } else {
            workoutDays.append(workoutDay)
        }
        
        // Save to persistent storage
        if useICloud {
            iCloudStore.set(data, forKey: key)
            iCloudStore.synchronize()
            print("☁️ Saved workout to iCloud: \(key)")
        }
        
        userDefaults.set(data, forKey: key)
        print("💾 Saved workout to UserDefaults: \(key)")
        
        return true
    }
    
    /// Get block info for a specific week number
    func getBlockForWeek(_ weekNumber: Int) -> (type: BlockType, weekInBlock: Int) {
        let week = ((weekNumber - 1) % 20) + 1
        
        if week <= 8 {
            return (.aerobicCapacity, week)
        } else if week == 9 {
            return (.deload, 1)
        } else if week <= 19 {
            return (.hypertrophyStrength, week - 9)
        } else {
            return (.deload, 1)
        }
    }
    
    /// Get the training block that contains a specific date
    func getBlockForDate(_ date: Date) -> TrainingBlock? {
        guard let program = currentProgram else { return nil }
        
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        
        for block in blocks {
            if block.contains(date: date) {
                return block
            }
        }
        
        return nil
    }
    
    // MARK: - Schedule Snapshot Generation for System Prompt Optimization
    
    /// Generate enhanced schedule snapshot for system prompt injection
    func generateScheduleSnapshot() -> String {
        // Auto-initialize program if none exists - using FIXED start date to avoid daily program creation
        if currentProgram == nil {
            print("🔄 DEBUG: currentProgram is nil during snapshot generation - attempting explicit load")
            loadProgram()
            
            if currentProgram == nil {
                // Use simulated time for start date - only initialize ONCE, not daily
                let startDate = Calendar.current.startOfDay(for: Date.current)
                print("🔄 Auto-initializing training program during snapshot generation with simulated start date: \(startDate)")
                startNewProgram(startDate: startDate)
            } else {
                print("✅ Found existing program after explicit load during snapshot generation")
            }
        }
        
        guard currentProgram != nil else {
            print("❌ Failed to auto-initialize program during snapshot generation")
            return "## CURRENT SCHEDULE SNAPSHOT\n**Status**: Error initializing training program"
        }
        
        let current = Date.current
        let weekDays = generateWeek(containing: current)
        
        print("🔍 SNAPSHOT_DEBUG: Generating enhanced snapshot for \(weekDays.count) days")
        
        var snapshot = generateBasicHeader(current: current)
        snapshot += generateTodaysFocus(current: current, weekDays: weekDays)
        snapshot += generateWeeklyProgression(current: current, weekDays: weekDays)
        snapshot += generateBlockContext()
        snapshot += generatePerformanceIndicators(weekDays: weekDays)
        
        print("🔍 SNAPSHOT_DEBUG: Enhanced snapshot generated (\(snapshot.count) characters)")
        
        return snapshot
    }
    
    // MARK: - Enhanced Schedule Snapshot Helper Methods
    
    /// Generate basic header with program info
    private func generateBasicHeader(current: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        var header = "## CURRENT SCHEDULE SNAPSHOT\n"
        header += "**Generated**: \(formatter.string(from: current))\n"
        header += "**Program**: Week \(totalWeekInProgram) of 20 - \(currentBlock?.type.rawValue.capitalized ?? "Unknown")-\(currentBlock?.type.rawValue == "hypertrophyStrength" ? "Strength" : (currentBlock?.type.rawValue.capitalized ?? "Unknown")) Block"
        
        if let block = currentBlock {
            header += " (Week \(currentWeekInBlock) of \(block.type.duration))\n\n"
        } else {
            header += "\n\n"
        }
        
        return header
    }
    
    /// Generate detailed today's focus section
    private func generateTodaysFocus(current: Date, weekDays: [WorkoutDay]) -> String {
        guard let todayWorkout = weekDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: current) }) else {
            return "### TODAY'S FOCUS\n**Status**: Unable to determine today's workout\n\n"
        }
        
        var focus = "### TODAY'S FOCUS\n"
        focus += "**\(todayWorkout.dayOfWeek.name)**: "
        
        // Get template info for context
        let template = getTemplateForDay(todayWorkout.dayOfWeek, blockType: todayWorkout.blockType)
        
        if todayWorkout.hasWorkout {
            if let structured = todayWorkout.structuredWorkout {
                // Coach-planned structured workout
                focus += "\(structured.title ?? "Workout")\n"
                focus += "- **Planned**: \(structured.displaySummary)\n"
                if let duration = structured.totalDuration {
                    focus += "- **Duration**: \(duration) minutes\n"
                }
                let distribution = structured.exerciseDistribution
                if distribution.cardio + distribution.strength + distribution.mobility + distribution.yoga > 0 {
                    var types: [String] = []
                    if distribution.cardio > 0 { types.append("cardio(\(distribution.cardio))") }
                    if distribution.strength > 0 { types.append("strength(\(distribution.strength))") }
                    if distribution.mobility > 0 { types.append("mobility(\(distribution.mobility))") }
                    if distribution.yoga > 0 { types.append("yoga(\(distribution.yoga))") }
                    focus += "- **Exercises**: \(types.joined(separator: ", "))\n"
                }
                if let notes = structured.notes, !notes.isEmpty {
                    focus += "- **Notes**: \(notes)\n"
                }
                focus += "- **Status**: Workout planned ⚡\n"
            } else if let planned = todayWorkout.plannedWorkout {
                // Legacy planned workout
                focus += "\(planned)\n"
                focus += "- **Status**: Workout planned ⚡\n"
            } else if todayWorkout.isTemplateGenerated {
                // Template-generated workout
                focus += "\(template?.title ?? "Template Workout")\n"
                if let template = template {
                    focus += "- **Template**: \(template.summary)\n"
                    focus += "- **Duration**: \(template.durationMinutes) minutes\n"
                    focus += "- **Focus**: \(template.focus)\n"
                    focus += "- **Intensity**: \(template.intensityZone)\n"
                }
                focus += "- **Status**: Template ready for customization 📋\n"
            }
        } else {
            // No workout planned
            focus += "NO WORKOUT PLANNED\n"
            if let template = template {
                focus += "- **Expected Template**: \(template.title)\n"
                focus += "- **Template Summary**: \(template.summary)\n"
                focus += "- **Expected Duration**: \(template.durationMinutes) minutes\n"
                focus += "- **Expected Focus**: \(template.focus)\n"
            }
            focus += "- **Status**: ⚡ [TOOL_CALL REQUIRED]\n"
        }
        
        return focus + "\n"
    }
    
    /// Generate weekly progression overview
    private func generateWeeklyProgression(current: Date, weekDays: [WorkoutDay]) -> String {
        var progression = "### THIS WEEK PROGRESSION\n"
        
        for day in weekDays {
            let dayName = day.dayOfWeek.name
            let isToday = Calendar.current.isDate(day.date, inSameDayAs: current)
            let template = getTemplateForDay(day.dayOfWeek, blockType: day.blockType)
            
            var dayLine = "- **\(dayName)"
            if isToday { dayLine += " (TODAY)" }
            dayLine += "**: "
            
            if day.hasWorkout {
                // Determine workout source and status
                if let structured = day.structuredWorkout {
                    dayLine += "\(structured.title ?? template?.title ?? "Workout") - \(structured.displaySummary)"
                    if let duration = structured.totalDuration {
                        dayLine += " (\(duration)')"
                    }
                    dayLine += isToday ? " ⚡ PLANNED" : " ✅ Completed"
                } else if let planned = day.plannedWorkout {
                    dayLine += planned
                    dayLine += isToday ? " ⚡ PLANNED" : " ✅ Completed"
                } else if day.isTemplateGenerated {
                    dayLine += "\(template?.title ?? "Template Workout") - \(template?.summary ?? "Workout template")"
                    if let template = template {
                        dayLine += " (\(template.durationMinutes)')"
                    }
                    dayLine += " 📋 Template"
                }
            } else {
                // No workout
                if let template = template {
                    dayLine += "\(template.title) - \(template.summary) (\(template.durationMinutes)')"
                    dayLine += isToday ? " ❌ NEEDS PLANNING" : " ⚪ Not planned"
                } else {
                    dayLine += "No workout"
                    dayLine += isToday ? " ❌ NEEDS PLANNING" : " ⚪ Not planned"
                }
            }
            
            progression += dayLine + "\n"
        }
        
        return progression + "\n"
    }
    
    /// Generate training block context
    private func generateBlockContext() -> String {
        guard let block = currentBlock else {
            return "### BLOCK PROGRESSION CONTEXT\n**Status**: No current training block\n\n"
        }
        
        var context = "### BLOCK PROGRESSION CONTEXT\n"
        context += "**\(block.type.rawValue.capitalized) Block Goals**:\n"
        
        switch block.type {
        case .hypertrophyStrength:
            context += "- Primary: Build muscle mass and base strength\n"
            context += "- Volume: High training volume with moderate intensity\n"
            context += "- Expected: 5-6 sessions/week, 2-3 strength + 3-4 aerobic\n"
            context += "- Week \(currentWeekInBlock) Focus: "
            if currentWeekInBlock <= 2 {
                context += "Establishing movement patterns and baseline loads\n"
            } else if currentWeekInBlock <= 6 {
                context += "Progressive overload and volume accumulation\n"
            } else {
                context += "Peak volume and strength adaptation\n"
            }
        case .aerobicCapacity:
            context += "- Primary: Develop aerobic power and capacity\n"
            context += "- Volume: Moderate-high aerobic volume with higher intensity\n"
            context += "- Expected: 5-6 sessions/week, focus on VO2max and threshold\n"
            context += "- Week \(currentWeekInBlock) Focus: "
            if currentWeekInBlock <= 2 {
                context += "Building aerobic base and introducing intervals\n"
            } else if currentWeekInBlock <= 5 {
                context += "High-intensity interval training and threshold work\n"
            } else {
                context += "Peak aerobic power and competition preparation\n"
            }
        case .deload:
            context += "- Primary: Recovery and adaptation\n"
            context += "- Volume: Reduced volume (-30%), maintain movement quality\n"
            context += "- Expected: 3-4 easy sessions, focus on mobility and technique\n"
            context += "- Week \(currentWeekInBlock) Focus: Active recovery and preparation for next block\n"
        case .racePrep:
            context += "- Primary: Race-specific preparation and peaking\n"
            context += "- Volume: Moderate volume with race-pace and threshold work\n"
            context += "- Expected: 5-6 sessions/week, focus on race simulation\n"
            context += "- Week \(currentWeekInBlock) Focus: Race-specific training and simulation\n"
        case .taper:
            context += "- Primary: Maintain fitness while recovering for peak performance\n"
            context += "- Volume: Significantly reduced volume, maintain intensity\n"
            context += "- Expected: 3-4 sessions/week, short and sharp\n"
            context += "- Week \(currentWeekInBlock) Focus: Final preparation and recovery for race\n"
        }
        
        return context + "\n"
    }
    
    /// Generate performance indicators
    private func generatePerformanceIndicators(weekDays: [WorkoutDay]) -> String {
        var indicators = "### RECENT PERFORMANCE INDICATORS\n"
        
        // Calculate completion metrics
        let completedWorkouts = weekDays.filter { $0.hasWorkout && !Calendar.current.isDate($0.date, inSameDayAs: Date.current) }.count
        let totalPlannedWorkouts = weekDays.filter { $0.hasWorkout }.count
        let remainingWorkouts = weekDays.filter { !$0.hasWorkout }.count
        
        indicators += "- **Volume Completion**: \(completedWorkouts)/\(totalPlannedWorkouts) sessions completed this week\n"
        
        // Block adherence
        _ = getExpectedSessionsForBlock()
        indicators += "- **Block Adherence**: On track with \(currentBlock?.type.rawValue ?? "training") block expectations\n"
        
        // Template vs custom analysis
        let templateWorkouts = weekDays.filter { $0.isTemplateGenerated }.count
        let customWorkouts = weekDays.filter { $0.isCoachCustomized }.count
        
        if customWorkouts > 0 {
            indicators += "- **Customization**: \(customWorkouts) coach-customized, \(templateWorkouts) template-based\n"
        }
        
        if remainingWorkouts > 0 {
            indicators += "- **Planning Needed**: \(remainingWorkouts) workout\(remainingWorkouts == 1 ? "" : "s") still need planning\n"
        }
        
        return indicators
    }
    
    /// Get expected number of sessions for current block type
    private func getExpectedSessionsForBlock() -> Int {
        guard let block = currentBlock else { return 5 }
        
        switch block.type {
        case .hypertrophyStrength, .aerobicCapacity:
            return 6  // 6 sessions per week (Monday rest)
        case .deload:
            return 4  // 4 sessions per week (reduced volume)
        case .racePrep:
            return 6  // 6 sessions per week (race prep volume)
        case .taper:
            return 3  // 3 sessions per week (minimal volume)
        }
    }
    
    /// Get workout template for a specific day and block type
    private func getTemplateForDay(_ dayOfWeek: DayOfWeek, blockType: BlockType) -> WorkoutTemplate? {
        return TrainingBlockTemplate.template(for: blockType)?.weeklyTemplate[dayOfWeek]
    }
}

// MARK: - DayOfWeek Extension

extension DayOfWeek {
    static func from(date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        // Calendar weekday: 1 = Sunday, 2 = Monday, etc.
        // Our enum: 0 = Monday, 1 = Tuesday, etc.
        let adjusted = (weekday + 5) % 7
        return DayOfWeek.allCases[adjusted]
    }
}