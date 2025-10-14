import Foundation

/// Generates calendar views (week/month) with workout data
/// Extracted from TrainingScheduleManager for better separation of concerns
class CalendarGenerator {
    
    // MARK: - Dependencies
    
    private let workoutStore: HybridCloudStore<WorkoutDay>
    private let blockScheduler: TrainingBlockScheduler
    
    // MARK: - Initialization
    
    init(workoutStore: HybridCloudStore<WorkoutDay>,
         blockScheduler: TrainingBlockScheduler) {
        self.workoutStore = workoutStore
        self.blockScheduler = blockScheduler
    }
    
    // MARK: - Week Generation
    
    /// Generate workout days for a specific week
    func generateWeek(
        containing date: Date,
        program: TrainingProgram?,
        blocks: [TrainingBlock]
    ) -> [WorkoutDay] {
        guard let program = program else {
            return []
        }
        
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        
        var days: [WorkoutDay] = []
        
        for dayOffset in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) {
                // Check if this date is before the program starts
                if dayDate < program.startDate {
                    // Create a pre-program rest day (no workout)
                    let preProgram = WorkoutDay(date: dayDate, blockType: .hypertrophyStrength)
                    days.append(preProgram)
                    continue
                }
                
                // Find which block contains this date
                guard let block = blocks.first(where: { $0.contains(date: dayDate) }) else {
                    // No block found, create blank day
                    let blankDay = WorkoutDay(date: dayDate, blockType: .hypertrophyStrength)
                    days.append(blankDay)
                    continue
                }
                
                // Try to load existing workout from storage
                if let savedDay = workoutStore.load(for: dayDate) {
                    days.append(savedDay)
                } else {
                    // Create blank workout day for this block
                    let workoutDay = WorkoutDay(date: dayDate, blockType: block.type)
                    days.append(workoutDay)
                }
            }
        }
        
        return days
    }
    
    // MARK: - Month Generation
    
    /// Generate workout days for a specific month
    func generateMonth(
        containing date: Date,
        program: TrainingProgram?,
        blocks: [TrainingBlock]
    ) -> [WorkoutDay] {
        guard let program = program else {
            return []
        }
        
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            return []
        }
        
        var days: [WorkoutDay] = []
        var currentDate = monthInterval.start
        
        while currentDate < monthInterval.end {
            // Find which block this date belongs to
            if let block = blocks.first(where: { $0.contains(date: currentDate) }) {
                // Try to load saved workout data
                if let savedDay = workoutStore.load(for: currentDate) {
                    days.append(savedDay)
                } else {
                    // Create blank workout day
                    let workoutDay = WorkoutDay(date: currentDate, blockType: block.type)
                    days.append(workoutDay)
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}