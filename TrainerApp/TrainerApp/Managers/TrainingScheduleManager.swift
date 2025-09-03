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
    func startNewProgram(startDate: Date = Date()) {
        let program = TrainingProgram(startDate: startDate, currentMacroCycle: 1)
        self.currentProgram = program
        saveProgram()
        updateCurrentBlock()
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
            return
        }
        
        let blocks = generateAllBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        let now = Date()
        
        // Find the current block
        for block in blocks {
            if block.contains(date: now) {
                self.currentBlock = block
                
                // Calculate week within block
                let calendar = Calendar.current
                let weeksSinceBlockStart = calendar.dateComponents([.weekOfYear], 
                                                                   from: block.startDate, 
                                                                   to: now).weekOfYear ?? 0
                self.currentWeekInBlock = weeksSinceBlockStart + 1
                break
            }
        }
        
        // Generate current week's workout days
        workoutDays = generateWeek(containing: Date())
    }
    
    /// Generate all training blocks for a macro-cycle
    private func generateAllBlocks(from startDate: Date, macroCycle: Int) -> [TrainingBlock] {
        print("🔍 DEBUG generateAllBlocks - Program start: \(startDate)")
        
        let calendar = Calendar.current
        let blockDurations: [(BlockType, Int)] = [
            (.aerobicCapacity, 8),
            (.deload, 1),
            (.hypertrophyStrength, 10),
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
        
        // Add race prep if race is scheduled
        if let raceDate = currentProgram?.raceDate,
           raceDate > currentStartDate {
            // Add race prep block
            let prepStart = calendar.date(byAdding: .weekOfYear, value: -3, to: raceDate)!
            blocks.append(TrainingBlock(
                type: .racePrep,
                startDate: prepStart,
                endDate: calendar.date(byAdding: .weekOfYear, value: -1, to: raceDate)!,
                weekNumber: blocks.count + 1
            ))
            
            // Add taper week
            let taperStart = calendar.date(byAdding: .weekOfYear, value: -1, to: raceDate)!
            blocks.append(TrainingBlock(
                type: .taper,
                startDate: taperStart,
                endDate: raceDate,
                weekNumber: 0 // Special case
            ))
        }
        
        return blocks
    }
    
    // MARK: - Calendar Generation
    
    /// Generate workout days for a specific week
    func generateWeek(containing date: Date) -> [WorkoutDay] {
        print("🔍 DEBUG generateWeek - Requested date: \(date)")
        print("🔍 DEBUG generateWeek - Current block: \(currentBlock?.type.rawValue ?? "nil")")
        
        // Find the appropriate block for the requested date, not just current block
        guard let program = currentProgram else {
            print("⚠️ DEBUG generateWeek - No current program")
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
                let workoutDay = WorkoutDay(date: dayDate, blockType: targetBlock.type)
                days.append(workoutDay)
            }
        }
        
        // Load any saved completion data
        loadWorkoutCompletions(for: &days)
        
        return days
    }
    
    /// Generate workout days for a specific month
    func generateMonth(containing date: Date) -> [WorkoutDay] {
        guard currentProgram != nil else { return [] }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        
        var days: [WorkoutDay] = []
        let blocks = generateAllBlocks(from: currentProgram!.startDate, macroCycle: currentProgram!.currentMacroCycle)
        
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            // Find which block this date belongs to
            if let block = blocks.first(where: { $0.contains(date: currentDate) }) {
                let workoutDay = WorkoutDay(date: currentDate, blockType: block.type)
                days.append(workoutDay)
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Load any saved completion data
        loadWorkoutCompletions(for: &days)
        
        return days
    }
    
    // MARK: - Workout Tracking
    
    /// Mark a workout as completed
    func markWorkoutCompleted(for day: WorkoutDay, notes: String? = nil, actualWorkout: String? = nil) {
        var updatedDay = day
        updatedDay.completed = true
        updatedDay.notes = notes
        updatedDay.actualWorkout = actualWorkout
        
        saveWorkoutCompletion(updatedDay)
        
        // Update the current days if needed
        if let index = workoutDays.firstIndex(where: { $0.date == day.date }) {
            workoutDays[index] = updatedDay
        }
    }
    
    /// Mark a workout as not completed
    func markWorkoutIncomplete(for day: WorkoutDay) {
        var updatedDay = day
        updatedDay.completed = false
        updatedDay.notes = nil
        updatedDay.actualWorkout = nil
        
        saveWorkoutCompletion(updatedDay)
        
        // Update the current days if needed
        if let index = workoutDays.firstIndex(where: { $0.date == day.date }) {
            workoutDays[index] = updatedDay
        }
    }
    
    /// Calculate days until next deload week
    func daysUntilNextDeload() -> Int? {
        guard let currentBlock = currentBlock else { return nil }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Check if we're in a deload block
        if currentBlock.type == .deload {
            return 0
        }
        
        // Calculate days until next deload based on block type
        switch currentBlock.type {
        case .aerobicCapacity:
            // Deload after 8 weeks
            let deloadStartDate = calendar.date(byAdding: .weekOfYear, value: 8, to: currentBlock.startDate) ?? today
            let days = calendar.dateComponents([.day], from: today, to: deloadStartDate).day ?? 0
            return max(0, days)
            
        case .hypertrophyStrength:
            // Deload after 10 weeks
            let deloadStartDate = calendar.date(byAdding: .weekOfYear, value: 10, to: currentBlock.startDate) ?? today
            let days = calendar.dateComponents([.day], from: today, to: deloadStartDate).day ?? 0
            return max(0, days)
            
        case .racePrep:
            // Race prep is usually the final block before taper
            let deloadStartDate = calendar.date(byAdding: .weekOfYear, value: 2, to: currentBlock.startDate) ?? today
            let days = calendar.dateComponents([.day], from: today, to: deloadStartDate).day ?? 0
            return max(0, days)
            
        case .taper:
            // Taper is already a form of deload
            return 0
            
        case .deload:
            return 0
        }
    }
    
    // MARK: - Persistence
    
    private func saveWorkoutCompletion(_ day: WorkoutDay) {
        let key = "workout_\(dateKey(for: day.date))"
        
        print("💾 TrainingScheduleManager: Saving workout for key: \(key)")
        if let instructions = day.detailedInstructions {
            print("✅ TrainingScheduleManager: Saving with \(instructions.sections.count) instruction sections")
        }
        
        if let data = try? JSONEncoder().encode(day) {
            // Save to local storage
            userDefaults.set(data, forKey: key)
            
            // Save to iCloud if available
            if useICloud {
                iCloudStore.set(data, forKey: key)
                iCloudStore.synchronize()
                print("☁️ TrainingScheduleManager: Saved to iCloud")
            } else {
                print("💾 TrainingScheduleManager: Saved to local storage only")
            }
        } else {
            print("❌ TrainingScheduleManager: Failed to encode workout day")
        }
    }
    
    private func loadWorkoutCompletions(for days: inout [WorkoutDay]) {
        for (index, day) in days.enumerated() {
            let key = "workout_\(dateKey(for: day.date))"
            var data: Data?
            
            // Try iCloud first
            if useICloud {
                data = iCloudStore.data(forKey: key)
            }
            
            // Fall back to local storage
            if data == nil {
                data = userDefaults.data(forKey: key)
            }
            
            if let data = data,
               let savedDay = try? JSONDecoder().decode(WorkoutDay.self, from: data) {
                print("📥 TrainingScheduleManager: Loading saved data for \(key)")
                days[index].completed = savedDay.completed
                days[index].notes = savedDay.notes
                days[index].actualWorkout = savedDay.actualWorkout
                days[index].detailedInstructions = savedDay.detailedInstructions
                
                if let instructions = savedDay.detailedInstructions {
                    print("✅ TrainingScheduleManager: Loaded \(instructions.sections.count) instruction sections")
                }
            }
        }
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Helper Methods
    
    /// Get a formatted string describing the current position in the program
    func getCurrentPositionDescription() -> String {
        guard let block = currentBlock else {
            return "No active program"
        }
        
        return "\(block.type.rawValue) - Week \(currentWeekInBlock) of \(block.type.duration)"
    }
    
    /// Schedule a race and adjust the program
    func scheduleRace(on date: Date) {
        guard var program = currentProgram else { return }
        
        program.raceDate = date
        self.currentProgram = program
        saveProgram()
        updateCurrentBlock()
    }
    
    /// Remove scheduled race
    func removeRace() {
        guard var program = currentProgram else { return }
        
        program.raceDate = nil
        self.currentProgram = program
        saveProgram()
        updateCurrentBlock()
    }
    
    /// Get the next block type
    func getNextBlockType() -> BlockType? {
        guard let currentBlock = currentBlock else { return nil }
        
        switch currentBlock.type {
        case .aerobicCapacity:
            return .deload
        case .deload:
            // Check if previous was aerobic or hypertrophy
            return .hypertrophyStrength // Simplified for now
        case .hypertrophyStrength:
            return .deload
        case .racePrep:
            return .taper
        case .taper:
            return nil
        }
    }
    
    /// Calculate days until next deload
    func calculateDaysUntilNextDeload() -> Int? {
        guard let currentBlock = currentBlock else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        switch currentBlock.type {
        case .aerobicCapacity, .hypertrophyStrength:
            // Days until end of current block (next block is deload)
            return calendar.dateComponents([.day], from: now, to: currentBlock.endDate).day
        case .deload:
            // In deload, so 0
            return 0
        default:
            return nil
        }
    }
    
    /// Calculate program completion percentage
    func calculateProgramCompletion() -> Double {
        guard let program = currentProgram else { return 0 }
        
        let calendar = Calendar.current
        // A full program is 20 weeks (140 days)
        let programEndDate = calendar.date(byAdding: .weekOfYear, value: 20, to: program.startDate) ?? program.startDate
        let totalDays = calendar.dateComponents([.day],
                                               from: program.startDate,
                                               to: programEndDate).day ?? 1
        let elapsedDays = calendar.dateComponents([.day],
                                                 from: program.startDate,
                                                 to: Date()).day ?? 0
        
        return min(Double(elapsedDays) / Double(totalDays) * 100, 100.0)
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
                                                              to: Date()).weekOfYear ?? 0
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
                                                              to: Date()).weekOfYear ?? 0
        return (weeksSinceStart % 20) + 1
    }
    
    /// Get current day of week
    var currentDay: DayOfWeek {
        return DayOfWeek.from(date: Date())
    }
    
    /// Get workout days for the current week
    var currentWeekDays: [WorkoutDay] {
        return generateWeek(containing: Date())
    }
    
    /// Start a new training program
    func startProgram(startDate: Date = Date()) {
        startNewProgram(startDate: startDate)
    }
    
    /// Restart training program
    func restartProgram(startDate: Date = Date()) {
        // Clear old program data
        currentProgram = nil
        workoutDays = []
        
        // Clear completion data
        if useICloud {
            iCloudStore.removeObject(forKey: programKey)
            // Clear workout completion keys
            for i in -30...30 {
                if let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) {
                    let key = "workout_\(dateKey(for: date))"
                    iCloudStore.removeObject(forKey: key)
                }
            }
            iCloudStore.synchronize()
        }
        
        // Clear local storage
        userDefaults.removeObject(forKey: programKey)
        for i in -30...30 {
            if let date = Calendar.current.date(byAdding: .day, value: i, to: Date()) {
                let key = "workout_\(dateKey(for: date))"
                userDefaults.removeObject(forKey: key)
            }
        }
        
        // Start fresh program
        startNewProgram(startDate: startDate)
    }
    
    /// Toggle completion status for a specific date
    func toggleDayCompletion(for date: Date) {
        guard let workoutDay = currentWeekDays.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) else { return }
        
        if workoutDay.completed {
            markWorkoutIncomplete(for: workoutDay)
        } else {
            markWorkoutCompleted(for: workoutDay)
        }
    }
    
    /// Update a workout day with new information
    func updateWorkoutDay(_ day: WorkoutDay) {
        print("📝 TrainingScheduleManager: Updating workout day for \(dateKey(for: day.date))")
        if let instructions = day.detailedInstructions {
            print("✅ TrainingScheduleManager: Has detailed instructions with \(instructions.sections.count) sections")
        } else {
            print("⚠️ TrainingScheduleManager: No detailed instructions")
        }
        
        saveWorkoutCompletion(day)
        
        // Update the current days array if needed
        if let index = workoutDays.firstIndex(where: { $0.date == day.date }) {
            workoutDays[index] = day
        }
    }
    
    /// Add a new workout day
    func addWorkoutDay(_ day: WorkoutDay) {
        workoutDays.append(day)
        saveWorkoutCompletion(day)
    }
    
    /// Get detailed workout plan for a specific day and block type
    func getDetailedWorkoutPlan(for dayOfWeek: DayOfWeek, blockType: BlockType? = nil) -> String {
        let block = blockType ?? currentBlock?.type ?? .aerobicCapacity
        
        switch block {
        case .aerobicCapacity:
            return getAerobicWorkout(for: dayOfWeek)
        case .hypertrophyStrength:
            return getHypertrophyWorkout(for: dayOfWeek)
        case .deload:
            return getDeloadWorkout(for: dayOfWeek)
        default:
            return "Rest or light activity"
        }
    }
    
    private func getAerobicWorkout(for dayOfWeek: DayOfWeek) -> String {
        switch dayOfWeek {
        case .monday:
            return "Steady State Row (60-70 min) @ 65-75% HR"
        case .tuesday:
            return "Recovery/Cross-Training (30-45 min)"
        case .wednesday:
            return "Tempo Work (3x8 min @ threshold, 2 min rest)"
        case .thursday:
            return "Recovery/Technique (30 min)"
        case .friday:
            return "Steady State Row (70-90 min) @ 65-75% HR"
        case .saturday:
            return "Long Steady Row (90+ min) @ 65-70% HR"
        case .sunday:
            return "Rest Day"
        }
    }
    
    private func getHypertrophyWorkout(for dayOfWeek: DayOfWeek) -> String {
        switch dayOfWeek {
        case .monday:
            return "Power Intervals (8x250m @ max) + Weights"
        case .tuesday:
            return "Steady State (45 min) + Upper Body"
        case .wednesday:
            return "Threshold Intervals (4x2000m @ 85-90%)"
        case .thursday:
            return "Recovery/Technique (30 min)"
        case .friday:
            return "Sprint Work (10x1min) + Lower Body"
        case .saturday:
            return "Race Pace Practice (2x2000m)"
        case .sunday:
            return "Rest Day"
        }
    }
    
    private func getDeloadWorkout(for dayOfWeek: DayOfWeek) -> String {
        switch dayOfWeek {
        case .monday, .wednesday, .friday:
            return "Easy Recovery Row (30-40 min) @ 60% HR"
        case .tuesday, .thursday:
            return "Active Recovery (walk/stretch)"
        case .saturday:
            return "Optional Light Activity"
        case .sunday:
            return "Rest Day"
        }
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