import Foundation

/// Days of the week for workout scheduling
enum DayOfWeek: Int, CaseIterable, Codable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7
    
    var name: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
    
    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
    
    
    /// Get workout type icon
    func workoutIcon(for blockType: BlockType) -> String {
        switch self {
        case .monday:
            return "bed.double.fill"
        case .tuesday:
            return blockType == .aerobicCapacity ? "figure.rower" : "figure.strengthtraining.traditional"
        case .wednesday:
            return blockType == .deload ? "figure.yoga" : "figure.rower"
        case .thursday:
            return blockType == .hypertrophyStrength ? "figure.strengthtraining.traditional" : "figure.rower"
        case .friday:
            return blockType == .taper ? "bed.double.fill" : "figure.mixed.cardio"
        case .saturday:
            return blockType == .hypertrophyStrength ? "figure.strengthtraining.traditional" : "figure.rower"
        case .sunday:
            return blockType == .hypertrophyStrength ? "figure.strengthtraining.traditional" : "bicycle"
        }
    }
}

/// Represents a single day in the training calendar
struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    var plannedWorkout: String?  // Changed to var to allow updates
    var isCoachPlanned: Bool = false  // Track if coach-generated vs template
    
    init(date: Date, blockType: BlockType, plannedWorkout: String? = nil) {
        self.date = date
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Convert from Sunday = 1 to Monday = 1
        self.dayOfWeek = DayOfWeek(rawValue: weekday == 1 ? 7 : weekday - 1) ?? .monday
        self.blockType = blockType
        
        if let workout = plannedWorkout {
            // Use provided workout
            self.plannedWorkout = workout
            self.isCoachPlanned = true
        } else {
            // Leave blank for coach to fill in later
            self.plannedWorkout = nil
            self.isCoachPlanned = false
        }
    }
}

/// Calendar view options
enum CalendarViewMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    
    var icon: String {
        switch self {
        case .week:
            return "calendar.day.timeline.left"
        case .month:
            return "calendar"
        }
    }
}