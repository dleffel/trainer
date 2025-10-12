import Foundation

// MARK: - Results Logging (Universal Schema)
struct WorkoutSetResult: Codable {
    // Universal fields
    let timestamp: Date
    let exerciseName: String
    let notes: String?
    
    // Strength training fields
    let setNumber: Int?
    let reps: Int?
    let loadLb: String?
    let rir: Int?
    
    // Cardio/interval fields
    let interval: Int?
    let time: String?
    let distance: String?
    let pace: String?
    let spm: Int?
    let hr: Int?
    let power: Int?
    let cadence: Int?
    
    // Deprecated fields (kept for backward compatibility)
    let loadKg: String?  // Deprecated: Use loadLb only
    let rpe: Int?        // Deprecated: Use rir only

    enum CodingKeys: String, CodingKey {
        // Universal
        case timestamp
        case exerciseName
        case notes
        
        // Strength
        case setNumber
        case reps
        case loadLb
        case rir
        
        // Cardio
        case interval
        case time
        case distance
        case pace
        case spm
        case hr
        case power
        case cadence
        
        // Deprecated (backward compatibility only)
        case loadKg
        case rpe
    }

    init(timestamp: Date,
         exerciseName: String,
         setNumber: Int? = nil,
         reps: Int? = nil,
         loadLb: String? = nil,
         rir: Int? = nil,
         interval: Int? = nil,
         time: String? = nil,
         distance: String? = nil,
         pace: String? = nil,
         spm: Int? = nil,
         hr: Int? = nil,
         power: Int? = nil,
         cadence: Int? = nil,
         notes: String? = nil,
         // Deprecated parameters
         loadKg: String? = nil,
         rpe: Int? = nil) throws {
        self.timestamp = timestamp
        self.exerciseName = exerciseName
        self.notes = notes
        
        // Strength fields
        self.setNumber = setNumber
        self.reps = reps
        self.loadLb = loadLb
        self.rir = rir
        
        // Cardio fields
        self.interval = interval
        self.time = time
        self.distance = distance
        self.pace = pace
        self.spm = spm
        self.hr = hr
        self.power = power
        self.cadence = cadence
        
        // Deprecated fields
        self.loadKg = loadKg
        self.rpe = rpe
        
        // Validate all fields after assignment
        try self.validate()
    }
    
    /// Validate the workout set result
    private func validate() throws {
        // Exercise name validation
        let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // Blacklist of invalid exercise names
        let invalidNames = ["unknown", "exercise", "workout", "movement", "n/a", ""]
        
        // Check empty, blacklist, and minimum length
        if trimmed.isEmpty || invalidNames.contains(lower) || trimmed.count < 2 {
            throw WorkoutSetResultError.invalidExerciseName
        }
        
        // Strength field validations
        if let rir = rir, rir < 0 || rir > 10 {
            throw WorkoutSetResultError.invalidRIR
        }
        
        if let reps = reps, reps <= 0 {
            throw WorkoutSetResultError.invalidReps
        }
        
        if let setNumber = setNumber, setNumber <= 0 {
            throw WorkoutSetResultError.invalidSetNumber
        }
        
        // Deprecated field validations (for backward compatibility)
        if let rpe = rpe, rpe < 1 || rpe > 10 {
            throw WorkoutSetResultError.invalidRPE
        }
        
        // Cardio field validations
        if let hr = hr, hr < 40 || hr > 220 {
            throw WorkoutSetResultError.invalidHeartRate
        }
        
        if let spm = spm, spm <= 0 {
            throw WorkoutSetResultError.invalidSPM
        }
        
        if let power = power, power <= 0 {
            throw WorkoutSetResultError.invalidPower
        }
        
        if let cadence = cadence, cadence <= 0 {
            throw WorkoutSetResultError.invalidCadence
        }
        
        if let interval = interval, interval <= 0 {
            throw WorkoutSetResultError.invalidInterval
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Universal fields
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.exerciseName = try container.decode(String.self, forKey: .exerciseName)
        self.notes = try? container.decode(String.self, forKey: .notes)
        
        // Strength fields
        self.setNumber = try? container.decode(Int.self, forKey: .setNumber)
        self.reps = try? container.decode(Int.self, forKey: .reps)
        self.loadLb = try? container.decode(String.self, forKey: .loadLb)
        self.rir = try? container.decode(Int.self, forKey: .rir)
        
        // Cardio fields
        self.interval = try? container.decode(Int.self, forKey: .interval)
        self.time = try? container.decode(String.self, forKey: .time)
        self.distance = try? container.decode(String.self, forKey: .distance)
        self.pace = try? container.decode(String.self, forKey: .pace)
        self.spm = try? container.decode(Int.self, forKey: .spm)
        self.hr = try? container.decode(Int.self, forKey: .hr)
        self.power = try? container.decode(Int.self, forKey: .power)
        self.cadence = try? container.decode(Int.self, forKey: .cadence)
        
        // Deprecated fields (backward compatibility)
        self.loadKg = try? container.decode(String.self, forKey: .loadKg)
        self.rpe = try? container.decode(Int.self, forKey: .rpe)
        
        // Validate all fields after assignment
        try self.validate()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Universal fields
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encodeIfPresent(notes, forKey: .notes)
        
        // Strength fields
        try container.encodeIfPresent(setNumber, forKey: .setNumber)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(loadLb, forKey: .loadLb)
        try container.encodeIfPresent(rir, forKey: .rir)
        
        // Cardio fields
        try container.encodeIfPresent(interval, forKey: .interval)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encodeIfPresent(pace, forKey: .pace)
        try container.encodeIfPresent(spm, forKey: .spm)
        try container.encodeIfPresent(hr, forKey: .hr)
        try container.encodeIfPresent(power, forKey: .power)
        try container.encodeIfPresent(cadence, forKey: .cadence)
        
        // Deprecated fields (still encode for backward compatibility)
        try container.encodeIfPresent(loadKg, forKey: .loadKg)
        try container.encodeIfPresent(rpe, forKey: .rpe)
    }
}

// MARK: - Error Types

enum WorkoutSetResultError: LocalizedError {
    case invalidExerciseName
    case invalidRIR
    case invalidRPE
    case invalidReps
    case invalidSetNumber
    case invalidHeartRate
    case invalidSPM
    case invalidPower
    case invalidCadence
    case invalidInterval
    
    var errorDescription: String? {
        switch self {
        case .invalidExerciseName:
            return "Exercise name must be specific (e.g., 'Bench Press', 'Squat'). Generic terms like 'exercise' or 'unknown' are not allowed, and name must be at least 2 characters."
        case .invalidRIR:
            return "RIR must be between 0 and 10"
        case .invalidRPE:
            return "RPE must be between 1 and 10"
        case .invalidReps:
            return "Reps must be a positive number"
        case .invalidSetNumber:
            return "Set number must be a positive number"
        case .invalidHeartRate:
            return "Heart rate must be between 40 and 220 BPM"
        case .invalidSPM:
            return "SPM (strokes/steps per minute) must be a positive number"
        case .invalidPower:
            return "Power must be a positive number (watts)"
        case .invalidCadence:
            return "Cadence must be a positive number (RPM)"
        case .invalidInterval:
            return "Interval number must be a positive number"
        }
    }
}
