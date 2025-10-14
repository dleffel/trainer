import Foundation

/// Repository for workout CRUD operations and persistence
/// Extracted from TrainingScheduleManager for better separation of concerns
class WorkoutRepository {
    
    // MARK: - Dependencies
    
    private let workoutStore: HybridCloudStore<WorkoutDay>
    private let blockScheduler: TrainingBlockScheduler
    
    // MARK: - Initialization
    
    init(workoutStore: HybridCloudStore<WorkoutDay>,
         blockScheduler: TrainingBlockScheduler) {
        self.workoutStore = workoutStore
        self.blockScheduler = blockScheduler
    }
    
    // MARK: - Basic CRUD
    
    /// Get workout for a specific date
    func getWorkout(for date: Date) -> WorkoutDay? {
        return workoutStore.load(for: date)
    }
    
    /// Save a workout
    func saveWorkout(_ workout: WorkoutDay) throws {
        try workoutStore.save(workout, for: workout.date)
    }
    
    /// Delete a workout
    func deleteWorkout(for date: Date) throws {
        try workoutStore.delete(for: date)
    }
    
    /// Clear workouts in a date range
    func clearWorkouts(from startDate: Date, to endDate: Date) throws {
        try workoutStore.clearRange(from: startDate, to: endDate)
    }
    
    // MARK: - Planning APIs
    
    /// Plan a single workout (text-based) for a specific date
    func planSingleWorkout(
        for date: Date,
        workout: String,
        notes: String?,
        icon: String?,
        program: TrainingProgram?,
        currentBlock: TrainingBlock?
    ) throws {
        // Find or create workout day
        if let existingDay = getWorkout(for: date) {
            // Update existing
            var updatedDay = existingDay
            if let notes = notes {
                updatedDay.plannedWorkout = "\(workout)\n\n📝 Notes: \(notes)"
            } else {
                updatedDay.plannedWorkout = workout
            }
            updatedDay.isCoachPlanned = true
            updatedDay.workoutIcon = icon
            
            try saveWorkout(updatedDay)
        } else {
            // Create new workout day
            var newDay = generateWorkoutDay(for: date, program: program, currentBlock: currentBlock)
            if let notes = notes {
                newDay.plannedWorkout = "\(workout)\n\n📝 Notes: \(notes)"
            } else {
                newDay.plannedWorkout = workout
            }
            newDay.isCoachPlanned = true
            newDay.workoutIcon = icon
            
            try saveWorkout(newDay)
        }
    }
    
    /// Plan a structured workout for a specific date
    func planStructuredWorkout(
        for date: Date,
        workout: StructuredWorkout,
        notes: String?,
        icon: String?,
        program: TrainingProgram?,
        currentBlock: TrainingBlock?
    ) throws {
        // Find or create workout day
        if let existingDay = getWorkout(for: date) {
            // Update existing
            var updatedDay = existingDay
            updatedDay.structuredWorkout = workout
            updatedDay.isCoachPlanned = true
            updatedDay.workoutIcon = icon
            
            try saveWorkout(updatedDay)
        } else {
            // Create new workout day
            var newDay = generateWorkoutDay(for: date, program: program, currentBlock: currentBlock)
            newDay.structuredWorkout = workout
            newDay.isCoachPlanned = true
            newDay.workoutIcon = icon
            
            try saveWorkout(newDay)
        }
    }
    
    // MARK: - Update APIs
    
    /// Update a single workout (replace existing)
    func updateSingleWorkout(for date: Date, workout: String, reason: String?) throws {
        guard let existingDay = getWorkout(for: date) else {
            throw WorkoutRepositoryError.workoutNotFound(date: date)
        }
        
        var updatedDay = existingDay
        updatedDay.plannedWorkout = workout
        try saveWorkout(updatedDay)
    }
    
    /// Update a structured workout (replace existing)
    func updateStructuredWorkout(
        for date: Date,
        workout: StructuredWorkout,
        notes: String?,
        icon: String?
    ) throws {
        guard let existingDay = getWorkout(for: date) else {
            throw WorkoutRepositoryError.workoutNotFound(date: date)
        }
        
        var updatedDay = existingDay
        updatedDay.structuredWorkout = workout
        updatedDay.workoutIcon = icon
        try saveWorkout(updatedDay)
    }
    
    /// Update workout for a specific date (create if doesn't exist)
    func updateWorkoutForDay(
        date: Date,
        workout: String,
        program: TrainingProgram?,
        currentBlock: TrainingBlock?
    ) throws {
        if let workoutDay = getWorkout(for: date) {
            var updatedDay = workoutDay
            updatedDay.plannedWorkout = workout
            updatedDay.isCoachPlanned = true
            try saveWorkout(updatedDay)
        } else {
            var newDay = generateWorkoutDay(for: date, program: program, currentBlock: currentBlock)
            newDay.plannedWorkout = workout
            newDay.isCoachPlanned = true
            try saveWorkout(newDay)
        }
    }
    
    // MARK: - Batch Operations
    
    /// Update workouts for a specific week
    func updateWeekWorkouts(
        weekDays: [WorkoutDay],
        workouts: [String: String]
    ) throws {
        var errors: [Error] = []
        
        for (dayName, workoutText) in workouts {
            // Find matching day by comparing lowercase names
            if let workoutDay = weekDays.first(where: { $0.dayOfWeek.name.lowercased() == dayName.lowercased() }) {
                var updatedDay = workoutDay
                updatedDay.plannedWorkout = workoutText
                updatedDay.isCoachPlanned = true
                
                do {
                    try saveWorkout(updatedDay)
                } catch {
                    errors.append(error)
                }
            }
        }
        
        if !errors.isEmpty {
            throw WorkoutRepositoryError.batchUpdateFailed(count: errors.count)
        }
    }
    
    // MARK: - Helpers
    
    /// Generate a workout day for a specific date
    private func generateWorkoutDay(
        for date: Date,
        program: TrainingProgram?,
        currentBlock: TrainingBlock?
    ) -> WorkoutDay {
        guard let program = program else {
            return WorkoutDay(date: date, blockType: .hypertrophyStrength)
        }
        
        let blocks = blockScheduler.generateBlocks(from: program.startDate, macroCycle: program.currentMacroCycle)
        let blockForDate = blockScheduler.getBlock(for: date, in: blocks)
        
        let targetBlock = blockForDate ?? currentBlock ?? TrainingBlock(
            type: .hypertrophyStrength,
            startDate: date,
            endDate: date,
            weekNumber: 1
        )
        
        return WorkoutDay(date: date, blockType: targetBlock.type)
    }
}

// MARK: - Errors

enum WorkoutRepositoryError: LocalizedError {
    case workoutNotFound(date: Date)
    case batchUpdateFailed(count: Int)
    
    var errorDescription: String? {
        switch self {
        case .workoutNotFound(let date):
            return "Workout not found for date: \(date)"
        case .batchUpdateFailed(let count):
            return "Failed to update \(count) workouts"
        }
    }
}