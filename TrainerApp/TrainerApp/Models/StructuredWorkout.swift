import Foundation

// MARK: - StructuredWorkout

/// Represents a complete structured workout with multiple exercises
struct StructuredWorkout: Codable, Identifiable {
    var id: UUID
    let title: String?
    let summary: String?
    let durationMinutes: Int?
    let notes: String?
    let exercises: [Exercise]
    
    // Custom initializer to handle missing id during decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate new UUID if id is missing from JSON
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = try? container.decode(String.self, forKey: .title)
        self.summary = try? container.decode(String.self, forKey: .summary)
        self.durationMinutes = try? container.decode(Int.self, forKey: .durationMinutes)
        self.notes = try? container.decode(String.self, forKey: .notes)
        self.exercises = try container.decode([Exercise].self, forKey: .exercises)
    }
    
    // Standard initializer for creating new instances
    init(title: String?, summary: String?, durationMinutes: Int?, notes: String?, exercises: [Exercise]) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.exercises = exercises
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, durationMinutes, notes, exercises
    }
    
    /// Auto-derive total duration from exercises if not specified
    var totalDuration: Int? {
        durationMinutes ?? exercises.compactMap { $0.estimatedDurationMinutes }.reduce(0, +)
    }
    
    /// Generate a brief summary for display
    var displaySummary: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        }
        if let title = title, !title.isEmpty {
            return title
        }
        return "\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")"
    }
    
    /// Count exercises by type for logging/display
    var exerciseDistribution: (cardio: Int, strength: Int, mobility: Int, yoga: Int, generic: Int) {
        var cardio = 0, strength = 0, mobility = 0, yoga = 0, generic = 0
        
        for exercise in exercises {
            switch exercise.detail {
            case .cardio:
                cardio += 1
            case .strength:
                strength += 1
            case .mobility:
                mobility += 1
            case .yoga:
                yoga += 1
            case .generic:
                generic += 1
            }
        }
        
        return (cardio, strength, mobility, yoga, generic)
    }
    
    /// Derive icon from first exercise if no explicit icon provided
    var derivedIcon: String {
        guard let firstExercise = exercises.first else { return "figure.mixed.cardio" }
        
        switch firstExercise.detail {
        case .cardio(let detail):
            switch detail.modality?.lowercased() {
            case "bike", "cycling": return "bicycle"
            case "row", "rowing": return "figure.rower"
            case "run", "running": return "figure.run"
            case "swim", "swimming": return "figure.pool.swim"
            default: return "figure.mixed.cardio"
            }
        case .strength:
            return "figure.strengthtraining.traditional"
        case .mobility:
            return "figure.flexibility"
        case .yoga:
            return "figure.yoga"
        case .generic:
            return "figure.mixed.cardio"
        }
    }
}

// MARK: - Exercise

/// Represents a single exercise within a workout
struct Exercise: Codable, Identifiable {
    var id: UUID
    let kind: String  // e.g., "cardioBike", "strength", "mobility", "yoga", "generic"
    let name: String?
    let focus: String?
    let equipment: String?
    let tags: [String]?
    let detail: ExerciseDetail
    
    // Custom initializer to handle missing id during decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate new UUID if id is missing from JSON
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.kind = try container.decode(String.self, forKey: .kind)
        self.name = try? container.decode(String.self, forKey: .name)
        self.focus = try? container.decode(String.self, forKey: .focus)
        self.equipment = try? container.decode(String.self, forKey: .equipment)
        self.tags = try? container.decode([String].self, forKey: .tags)
        self.detail = try container.decode(ExerciseDetail.self, forKey: .detail)
    }
    
    // Standard initializer for creating new instances
    init(kind: String, name: String?, focus: String?, equipment: String?, tags: [String]?, detail: ExerciseDetail) {
        self.id = UUID()
        self.kind = kind
        self.name = name
        self.focus = focus
        self.equipment = equipment
        self.tags = tags
        self.detail = detail
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, focus, equipment, tags, detail
    }
    
    /// Estimate duration for this exercise (best effort)
    var estimatedDurationMinutes: Int? {
        switch detail {
        case .cardio(let cardioDetail):
            return cardioDetail.total?.durationMinutes
        case .strength(let strengthDetail):
            // Rough estimate: sets * (rest time + work time estimate)
            let setCount = strengthDetail.sets?.count ?? 0
            let avgRest = strengthDetail.sets?.compactMap { $0.restSeconds }.reduce(0, +) ?? 0
            let restMinutes = avgRest / 60
            let workEstimate = setCount * 2 // rough 2 min per set work
            return restMinutes + workEstimate
        case .mobility(let mobilityDetail):
            return mobilityDetail.blocks?.compactMap { $0.estimatedMinutes }.reduce(0, +)
        case .yoga(let yogaDetail):
            return yogaDetail.blocks?.compactMap { $0.durationMinutes }.reduce(0, +)
        case .generic:
            return nil
        }
    }
}

// MARK: - ExerciseDetail

/// Discriminated union for different exercise types
enum ExerciseDetail: Codable {
    case cardio(CardioDetail)
    case strength(StrengthDetail)
    case mobility(MobilityDetail)
    case yoga(YogaDetail)
    case generic(GenericDetail)
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type.lowercased() {
        case "cardio":
            let detail = try CardioDetail(from: decoder)
            self = .cardio(detail)
        case "strength":
            let detail = try StrengthDetail(from: decoder)
            self = .strength(detail)
        case "mobility":
            let detail = try MobilityDetail(from: decoder)
            self = .mobility(detail)
        case "yoga":
            let detail = try YogaDetail(from: decoder)
            self = .yoga(detail)
        default:
            let detail = try GenericDetail(from: decoder)
            self = .generic(detail)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .cardio(let detail):
            try container.encode("cardio", forKey: .type)
            try detail.encode(to: encoder)
        case .strength(let detail):
            try container.encode("strength", forKey: .type)
            try detail.encode(to: encoder)
        case .mobility(let detail):
            try container.encode("mobility", forKey: .type)
            try detail.encode(to: encoder)
        case .yoga(let detail):
            try container.encode("yoga", forKey: .type)
            try detail.encode(to: encoder)
        case .generic(let detail):
            try container.encode("generic", forKey: .type)
            try detail.encode(to: encoder)
        }
    }
}

// MARK: - Cardio Detail

struct CardioDetail: Codable {
    let modality: String?  // "bike", "run", "row", "swim", etc.
    let total: CardioTotal?
    let segments: [CardioSegment]?
    
    /// Get total duration from segments if total not specified
    var effectiveTotal: CardioTotal? {
        if let total = total {
            return total
        }
        
        // Try to calculate from segments
        guard let segments = segments else { return nil }
        
        var totalMinutes = 0
        for segment in segments {
            let repeatCount = segment.repeat ?? 1
            let workTime = segment.work?.durationMinutes ?? 0
            let restTime = segment.rest?.durationMinutes ?? 0
            totalMinutes += repeatCount * (workTime + restTime)
        }
        
        return totalMinutes > 0 ? CardioTotal(durationMinutes: totalMinutes, distanceMeters: nil) : nil
    }
}

struct CardioTotal: Codable {
    let durationMinutes: Int?
    let distanceMeters: Int?
}

struct CardioSegment: Codable {
    let `repeat`: Int?
    let work: CardioInterval?
    let rest: CardioInterval?
}

struct CardioInterval: Codable {
    let durationMinutes: Int?
    let distanceMeters: Int?
    let target: CardioTarget?
}

struct CardioTarget: Codable {
    let hrZone: String?
    let pace: String?
    let power: String?
    let rpe: String?
    let cadence: String?
}

// MARK: - Strength Detail

struct StrengthDetail: Codable {
    let movement: String?
    let sets: [StrengthSet]?
    let superset: String?  // Group sets under the same superset label
}

struct StrengthSet: Codable {
    let set: Int
    let reps: RepValue?
    let weight: String?
    let rir: Int?  // Reps in reserve
    let tempo: String?  // e.g., "2-0-2"
    let restSeconds: Int?
}

/// Flexible rep value that can be either an integer or a string (e.g., "max-2", "AMRAP")
enum RepValue: Codable {
    case integer(Int)
    case string(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(RepValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String for reps"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
    
    /// Get the display string for UI purposes
    var displayValue: String {
        switch self {
        case .integer(let value):
            return "\(value)"
        case .string(let value):
            return value
        }
    }
    
    /// Extract integer value if possible (useful for calculations)
    var intValue: Int? {
        switch self {
        case .integer(let value):
            return value
        case .string(let value):
            // Try to extract number from strings like "max-2" -> 2
            if value.lowercased().contains("max") {
                let components = value.components(separatedBy: CharacterSet.decimalDigits.inverted)
                return components.compactMap { Int($0) }.first
            }
            // For pure numeric strings
            return Int(value)
        }
    }
}

// MARK: - Mobility Detail

struct MobilityDetail: Codable {
    let blocks: [MobilityBlock]?
}

struct MobilityBlock: Codable {
    let name: String
    let holdSeconds: Int?
    let sides: Int?  // 1 = single side, 2 = both sides
    let reps: Int?   // For dynamic movements
    
    /// Estimate time for this block
    var estimatedMinutes: Int? {
        let sideMultiplier = sides ?? 1
        if let holdSeconds = holdSeconds {
            return (holdSeconds * sideMultiplier) / 60
        } else if let reps = reps {
            // Rough estimate: 3 seconds per rep
            return (reps * 3 * sideMultiplier) / 60
        }
        return nil
    }
}

// MARK: - Yoga Detail

struct YogaDetail: Codable {
    let blocks: [YogaBlock]?
}

struct YogaBlock: Codable {
    let name: String
    let durationMinutes: Int?
    let poses: [String]?  // Optional list of pose names
}

// MARK: - Generic Detail

struct GenericDetail: Codable {
    let items: [String]?
    let notes: String?
}