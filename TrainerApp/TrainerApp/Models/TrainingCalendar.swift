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
    
    
}

/// Workout type icons for coach selection
enum WorkoutType: String, CaseIterable {
    case rest = "bed.double.fill"
    case rowing = "figure.rower"
    case cycling = "bicycle"
    case running = "figure.run"
    case strength = "figure.strengthtraining.traditional"
    case yoga = "figure.yoga"
    case swimming = "figure.pool.swim"
    case crossTraining = "figure.mixed.cardio"
    case recovery = "heart.fill"
    case testing = "chart.line.uptrend.xyaxis"
    case noWorkout = "calendar.badge.exclamationmark"
    
    var icon: String {
        return self.rawValue
    }
}

/// Represents a single day in the training calendar
struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    var plannedWorkout: String?  // Legacy field - kept for backward compatibility, read-only
    var isCoachPlanned: Bool = false  // Track if coach-generated
    var workoutIcon: String?  // Coach-selected icon (SF Symbol name)
    
    // Structured workout data
    var structuredWorkout: StructuredWorkout?
    
    init(date: Date, blockType: BlockType, plannedWorkout: String? = nil) {
        self.date = date
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Convert from Sunday = 1 to Monday = 1
        self.dayOfWeek = DayOfWeek(rawValue: weekday == 1 ? 7 : weekday - 1) ?? .monday
        self.blockType = blockType
        
        if let workout = plannedWorkout {
            // Use provided workout (legacy path)
            self.plannedWorkout = workout
            self.isCoachPlanned = true
        } else {
            // Leave blank for coach to fill in later
            self.plannedWorkout = nil
            self.isCoachPlanned = false
        }
    }
    
    /// Check if this day has any workout content (structured or legacy)
    var hasWorkout: Bool {
        return structuredWorkout != nil || plannedWorkout != nil
    }
    
    /// Get the display icon for this workout day
    var displayIcon: String {
        // Priority 1: Coach-selected icon
        if let workoutIcon = workoutIcon {
            return workoutIcon
        }
        
        // Priority 2: Derive from structured workout
        if let structured = structuredWorkout {
            return structured.derivedIcon
        }
        
        // Priority 3: No workout indicator
        return WorkoutType.noWorkout.icon
    }
    
    /// Get a summary for display (structured takes priority, then legacy)
    var displaySummary: String? {
        if let structured = structuredWorkout {
            return structured.displaySummary
        }
        
        if let planned = plannedWorkout {
            return planned
        }
        
        return nil
    }
    
    /// Check if this is a coach-customized workout (vs blank)
    var isCoachCustomized: Bool {
        return isCoachPlanned || structuredWorkout != nil
    }
    
    /// Get the workout status for UI display
    var workoutStatus: WorkoutStatus {
        if isCoachCustomized {
            return .coachPlanned
        } else {
            return .blank
        }
    }
}

/// Represents the status of a workout day for UI purposes
enum WorkoutStatus: String, CaseIterable {
    case blank = "Blank"
    case coachPlanned = "Coach Planned"
    
    var icon: String {
        switch self {
        case .blank:
            return "calendar.badge.exclamationmark"
        case .coachPlanned:
            return "checkmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .blank:
            return "gray"
        case .coachPlanned:
            return "green"
        }
    }
}
