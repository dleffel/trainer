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
    
    /// Get the planned workout for this day based on the training template
    func plannedWorkout(for blockType: BlockType) -> String? {
        switch self {
        case .monday:
            return "Full Rest — metrics & recovery only"
            
        case .tuesday:
            switch blockType {
            case .aerobicCapacity:
                return "RowErg 70-80′ UT2 @ 18-20 spm"
            case .hypertrophyStrength:
                return "Back-squat 5×5, Trap-bar RDL 3×8, DB Split-Squat 3×10"
            case .deload:
                return "Light RowErg 40′ easy"
            case .racePrep:
                return "Power Clean 5×3 @ 60%, Depth Jump 3×5"
            case .taper:
                return "Light technique work 30′"
            }
            
        case .wednesday:
            switch blockType {
            case .aerobicCapacity:
                return "RowErg 35-40′ steady @ 20-22 spm"
            case .hypertrophyStrength:
                return "RowErg 30-40′ UT2 @ 18-20 spm + mobility"
            case .deload:
                return "Yoga/Mobility 45′"
            case .racePrep:
                return "RowErg 4×250m starts @ 38-44 spm"
            case .taper:
                return "Easy spin bike 30′"
            }
            
        case .thursday:
            switch blockType {
            case .aerobicCapacity:
                return "RowErg 4×10′ @ 85-88% HR @ 24-26 spm"
            case .hypertrophyStrength:
                return "Floor/Bench press 4×6, Pendlay Row 4×6, Pull-ups AMRAP"
            case .deload:
                return "Light upper body 3×10"
            case .racePrep:
                return "RowErg 6×500m @ 2k pace @ 30-32 spm"
            case .taper:
                return "Race pace 2×500m"
            }
            
        case .friday:
            switch blockType {
            case .aerobicCapacity:
                return "Strength maintenance — Squat 3×5, Press 3×5, Row 3×5"
            case .hypertrophyStrength:
                return "RowErg 5×6′ @ AT @ 26-28 spm"
            case .deload:
                return "Rest or easy bike 30′"
            case .racePrep:
                return "RowErg 8×500m @ 2k pace @ 32-34 spm"
            case .taper:
                return "Rest"
            }
            
        case .saturday:
            switch blockType {
            case .aerobicCapacity:
                return "RowErg 60′ with 10×1′ surges @ 30-32 spm"
            case .hypertrophyStrength:
                return "Front-squat 4×6, Power Clean 6×3, Hip-Thrust 3×10"
            case .deload:
                return "Easy RowErg 45′"
            case .racePrep:
                return "RowErg 3×750m @ race pace @ 30-32 spm"
            case .taper:
                return "Race prep: warm-up routine"
            }
            
        case .sunday:
            switch blockType {
            case .aerobicCapacity:
                return "Spin Bike 60′ easy + mobility"
            case .hypertrophyStrength:
                return "Standing OHP 4×6, Weighted Dip 3×8, Face-Pull 3×15"
            case .deload:
                return "Walk/Hike 60-90′"
            case .racePrep:
                return "Spin Bike 45′ flush + mobility"
            case .taper:
                return "Rest or light mobility"
            }
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

/// Represents detailed workout instructions
struct WorkoutInstructions: Codable, Identifiable {
    let id = UUID()
    let generatedAt: Date
    let sections: [InstructionSection]
    
    /// Quick access to formatted text for display
    var formattedText: String {
        sections.map { $0.formattedContent }.joined(separator: "\n\n")
    }
}

/// Represents a section of workout instructions
struct InstructionSection: Codable {
    enum SectionType: String, Codable, CaseIterable {
        case overview = "Overview"
        case heartRateZones = "Heart Rate Zones"
        case warmUp = "Warm-up"
        case mainSet = "Main Set"
        case coolDown = "Cool-down"
        case technique = "Technique Focus"
        case hydration = "Hydration"
        case nutrition = "Nutrition"
        case recovery = "Recovery"
        case alternatives = "Alternative Options"
        case notes = "Additional Notes"
    }
    
    let type: SectionType
    let title: String
    let content: [String] // Array for bullet points or paragraphs
    
    var formattedContent: String {
        var result = "## \(title)\n"
        result += content.map { "• \($0)" }.joined(separator: "\n")
        return result
    }
}

/// Represents a single day in the training calendar
struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    let plannedWorkout: String?
    var completed: Bool = false
    var notes: String?
    var actualWorkout: String?
    
    // New field for detailed instructions
    var detailedInstructions: WorkoutInstructions?
    
    init(date: Date, blockType: BlockType) {
        self.date = date
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Convert from Sunday = 1 to Monday = 1
        self.dayOfWeek = DayOfWeek(rawValue: weekday == 1 ? 7 : weekday - 1) ?? .monday
        self.blockType = blockType
        self.plannedWorkout = dayOfWeek.plannedWorkout(for: blockType)
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