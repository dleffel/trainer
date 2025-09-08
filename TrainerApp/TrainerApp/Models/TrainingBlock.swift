import Foundation

/// Represents different types of training blocks in the program
enum BlockType: String, CaseIterable, Codable {
    case aerobicCapacity = "Aerobic Capacity"
    case hypertrophyStrength = "Hypertrophy-Strength"
    case deload = "Deload"
    case racePrep = "Race Prep"
    case taper = "Taper"
    
    /// Duration in weeks for each block type
    var duration: Int {
        switch self {
        case .aerobicCapacity:
            return 8
        case .hypertrophyStrength:
            return 10
        case .deload:
            return 1
        case .racePrep:
            return 12
        case .taper:
            return 2
        }
    }
    
    /// Color representation for UI
    var color: String {
        switch self {
        case .aerobicCapacity:
            return "blue"
        case .hypertrophyStrength:
            return "orange"
        case .deload:
            return "green"
        case .racePrep:
            return "red"
        case .taper:
            return "purple"
        }
    }
    
    /// Icon for the block type
    var icon: String {
        switch self {
        case .aerobicCapacity:
            return "lungs.fill"
        case .hypertrophyStrength:
            return "figure.strengthtraining.traditional"
        case .deload:
            return "leaf.fill"
        case .racePrep:
            return "flag.checkered"
        case .taper:
            return "arrow.down.right"
        }
    }
}

/// Represents a training block within the program
struct TrainingBlock: Codable, Identifiable {
    let id = UUID()
    let type: BlockType
    let startDate: Date
    let endDate: Date
    let weekNumber: Int // Week number within the macro-cycle
    
    /// Calculate which week we're currently in within this block
    func currentWeek(from date: Date = Date.current) -> Int? {
        guard date >= startDate && date <= endDate else { return nil }
        
        let calendar = Calendar.current
        let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: startDate, to: date).weekOfYear ?? 0
        return weeksSinceStart + 1
    }
    
    /// Check if a date falls within this block
    func contains(date: Date) -> Bool {
        return date >= startDate && date <= endDate
    }
}

/// Represents the overall training program
struct TrainingProgram: Codable {
    let startDate: Date
    var currentMacroCycle: Int // 1-4
    var raceDate: Date?
    var lastModified: Date
    
    init(startDate: Date = Date.current, currentMacroCycle: Int = 1) {
        self.startDate = startDate
        self.currentMacroCycle = currentMacroCycle
        self.raceDate = nil
        self.lastModified = Date.current
    }
    
    /// Calculate total weeks since program start
    func totalWeeks(from date: Date = Date.current) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.weekOfYear], from: startDate, to: date).weekOfYear ?? 0
    }
}