import Foundation

// MARK: - Results Logging (Per-Set)
struct WorkoutSetResult: Codable {
    let timestamp: Date
    let exerciseName: String
    let setNumber: Int?
    let reps: Int?
    let loadLb: String?
    let loadKg: String?
    let rir: Int?
    let rpe: Int?
    let notes: String?

    // Support legacy/alias keys (e.g., "exercise", "set") while encoding canonical keys
    enum CodingKeys: String, CodingKey {
        case timestamp
        case exerciseName
        case setNumber
        case reps
        case loadLb
        case loadKg
        case rir
        case rpe
        case notes

        // Aliases that may appear in incoming tool calls or legacy payloads
        case exercise        // alias for exerciseName
        case set             // alias for setNumber
    }

    init(timestamp: Date,
         exerciseName: String,
         setNumber: Int?,
         reps: Int?,
         loadLb: String?,
         loadKg: String?,
         rir: Int?,
         rpe: Int?,
         notes: String?) throws {
        self.timestamp = timestamp
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.loadLb = loadLb
        self.loadKg = loadKg
        self.rir = rir
        self.rpe = rpe
        self.notes = notes
        
        // Validate all fields after assignment
        try self.validate()
    }
    
    /// Validate the workout set result
    private func validate() throws {
        // Exercise name validation
        if exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorkoutSetResultError.invalidExerciseName
        }
        
        // RIR validation (0-10 scale)
        if let rir = rir, rir < 0 || rir > 10 {
            throw WorkoutSetResultError.invalidRIR
        }
        
        // RPE validation (1-10 scale)
        if let rpe = rpe, rpe < 1 || rpe > 10 {
            throw WorkoutSetResultError.invalidRPE
        }
        
        // Reps validation (must be positive)
        if let reps = reps, reps <= 0 {
            throw WorkoutSetResultError.invalidReps
        }
        
        // Set number validation (must be positive)
        if let setNumber = setNumber, setNumber <= 0 {
            throw WorkoutSetResultError.invalidSetNumber
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Prefer canonical key; fall back to alias, but require exercise name
        if let exerciseName = try? container.decode(String.self, forKey: .exerciseName) {
            self.exerciseName = exerciseName
        } else if let exercise = try? container.decode(String.self, forKey: .exercise) {
            self.exerciseName = exercise
        } else {
            throw DecodingError.keyNotFound(CodingKeys.exerciseName,
                DecodingError.Context(codingPath: decoder.codingPath,
                                    debugDescription: "Exercise name is required but missing"))
        }
        
        // Prefer canonical key; fall back to alias
        self.setNumber = (try? container.decode(Int.self, forKey: .setNumber))
            ?? (try? container.decode(Int.self, forKey: .set))
        self.reps = try? container.decode(Int.self, forKey: .reps)
        self.loadLb = try? container.decode(String.self, forKey: .loadLb)
        self.loadKg = try? container.decode(String.self, forKey: .loadKg)
        self.rir = try? container.decode(Int.self, forKey: .rir)
        self.rpe = try? container.decode(Int.self, forKey: .rpe)
        self.notes = try? container.decode(String.self, forKey: .notes)
        
        // Validate all fields after assignment
        try self.validate()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encodeIfPresent(setNumber, forKey: .setNumber)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(loadLb, forKey: .loadLb)
        try container.encodeIfPresent(loadKg, forKey: .loadKg)
        try container.encodeIfPresent(rir, forKey: .rir)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

// MARK: - Error Types

enum WorkoutSetResultError: LocalizedError {
    case invalidExerciseName
    case invalidRIR
    case invalidRPE
    case invalidReps
    case invalidSetNumber
    
    var errorDescription: String? {
        switch self {
        case .invalidExerciseName:
            return "Exercise name cannot be empty"
        case .invalidRIR:
            return "RIR must be between 0 and 10"
        case .invalidRPE:
            return "RPE must be between 1 and 10"
        case .invalidReps:
            return "Reps must be a positive number"
        case .invalidSetNumber:
            return "Set number must be a positive number"
        }
    }
}
