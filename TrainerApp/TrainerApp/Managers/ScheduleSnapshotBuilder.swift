import Foundation

/// Builds comprehensive schedule reports and snapshots
/// Extracted from TrainingScheduleManager for better separation of concerns
class ScheduleSnapshotBuilder {
    
    // MARK: - Dependencies
    
    private let workoutStore: HybridCloudStore<WorkoutDay>
    private let resultsManager: WorkoutResultsManager
    
    // MARK: - Initialization
    
    init(workoutStore: HybridCloudStore<WorkoutDay>,
         resultsManager: WorkoutResultsManager = .shared) {
        self.workoutStore = workoutStore
        self.resultsManager = resultsManager
    }
    
    // MARK: - Public Methods
    
    /// Generate current training block context for the coach
    func buildBlockContext(
        currentBlock: TrainingBlock?,
        currentWeekInBlock: Int,
        totalWeek: Int,
        programStartDate: Date?
    ) -> String {
        guard let block = currentBlock, let startDate = programStartDate else {
            return "## CURRENT TRAINING BLOCK\n\nNo active training program.\n"
        }
        
        var context = "## CURRENT TRAINING BLOCK\n\n"
        
        // PURE STATE ONLY - no interpretation or guidance
        context += "**Block Type**: \(block.type.rawValue)\n"
        context += "**Week in Block**: \(currentWeekInBlock) of \(block.type.duration)\n"
        context += "**Total Week in Program**: \(totalWeek) of 20\n"
        context += "**Program Started**: \(WorkoutFormatter.formatDate(startDate))\n"
        
        return context
    }
    
    /// Generate a comprehensive schedule snapshot showing exercises from specified date range with results
    func buildSnapshot(
        from startDate: Date,
        to endDate: Date
    ) -> String {
        let calendar = Calendar.current
        
        // Start building the snapshot with dynamic date range
        var snapshot = "## SCHEDULE SNAPSHOT\n"
        snapshot += "Range: \(WorkoutFormatter.formatDate(startDate)) to \(WorkoutFormatter.formatDate(endDate))\n"
        snapshot += "Generated: \(WorkoutFormatter.formatDateTime(endDate))\n\n"
        
        // Iterate through each date from start to end
        var currentDate = startDate
        var daysProcessed = 0
        
        while currentDate <= endDate {
            // Load workout for this date
            if let workoutDay = workoutStore.load(for: currentDate) {
                // Load results for this date
                let results = resultsManager.loadSetResults(for: currentDate)
                
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
    
    /// Convenience method for building a snapshot for the last 30 days
    func buildRecentSnapshot(endingOn endDate: Date = Date.current) -> String {
        let calendar = Calendar.current
        
        guard let startDate = calendar.date(byAdding: .day, value: -30, to: endDate) else {
            return "Unable to calculate date range for schedule snapshot"
        }
        
        var snapshot = buildSnapshot(from: startDate, to: endDate)
        // Replace generic header with "Last 30 Days" for this convenience method
        snapshot = snapshot.replacingOccurrences(of: "## SCHEDULE SNAPSHOT\n", with: "## SCHEDULE SNAPSHOT (Last 30 Days)\n")
        return snapshot
    }
    
    // MARK: - Private Helpers
    
    /// Format a single day's entry with workout and results
    private func formatDayEntry(workoutDay: WorkoutDay, results: [WorkoutSetResult]) -> String {
        var entry = ""
        
        // Only show days that have a workout
        guard workoutDay.hasWorkout else {
            return entry
        }
        
        // Date header
        entry += "### \(WorkoutFormatter.formatDate(workoutDay.date)) - \(workoutDay.dayOfWeek.name)\n"
        
        // Check if we have structured workout
        if let workout = workoutDay.structuredWorkout {
            entry += "**Scheduled Exercises:**\n"
            
            for (index, exercise) in workout.exercises.enumerated() {
                let exerciseName = WorkoutFormatter.formatExerciseName(exercise)
                entry += "\(index + 1). \(exerciseName)\n"
                entry += "   - Planned: \(WorkoutFormatter.formatExerciseDetails(exercise))\n"
                
                // Match and format results for this exercise
                let exerciseResults = WorkoutFormatter.matchResultsToExercise(exerciseName: exerciseName, results: results)
                if !exerciseResults.isEmpty {
                    entry += "   - Results:\n"
                    entry += WorkoutFormatter.formatResultsForExercise(exerciseResults)
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
                entry += WorkoutFormatter.formatAllResults(results)
            }
            entry += "\n"
        }
        
        return entry
    }
}