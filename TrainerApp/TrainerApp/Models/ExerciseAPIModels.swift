import Foundation

// MARK: - Enumerations

/// Primary modality for a workout day
enum APIDayPrimaryModality: String, Codable {
    case strength
    case rowing
    case spinning
    case running
    case mobility
    case hiking
    case rest
    case swimming      // Pool or open water workouts
    case crossTraining // Mixed-modality training
    case testing       // Fitness assessment (VO2max, FTP, etc.)
}

/// Cardio modality types
enum APICardioModality: String, Codable {
    case rowing
    case spinning
    case running
}

/// Weight unit for strength exercises
enum APIStrengthUnit: String, Codable {
    case lb
    case kg
}

// MARK: - Exercise Entry

struct ExerciseEntryRequest: Codable {
    let primaryModality: String?
    let dayNotes: String?
}

struct ExerciseEntryResponse: Codable {
    let id: String
    let date: String
    let primaryModality: String?
    let dayNotes: String?
    let createdAt: String?
    let updatedAt: String?
    let userId: String?
}

struct ExerciseEntryWithItems: Codable {
    let id: String
    let date: String
    let primaryModality: String?
    let dayNotes: String?
    let createdAt: String?
    let updatedAt: String?
    let userId: String?
    let strengthExercises: [StrengthExerciseResponse]?
    let cardioWorkouts: [CardioWorkoutResponse]?
    let yogaMobilityWorkout: YogaMobilityResponse?
}

// MARK: - Strength Exercises

struct StrengthExerciseRequest: Codable {
    let name: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
}

struct StrengthExerciseResponse: Codable {
    let id: String
    let name: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let exerciseEntryId: String?
    let sets: [StrengthSetResponse]?
}

// MARK: - Strength Sets

struct StrengthSetRequest: Codable {
    let completed: Bool?
    let reps: Int?
    let load: Double?
    let unit: String?
    let rir: Int?
    let notes: String?
    let targetReps: String?
    let targetLoad: String?
    let targetRir: String?
    let displayOrder: Int?
    
    init(
        completed: Bool? = nil,
        reps: Int? = nil,
        load: Double? = nil,
        unit: String? = nil,
        rir: Int? = nil,
        notes: String? = nil,
        targetReps: String? = nil,
        targetLoad: String? = nil,
        targetRir: String? = nil,
        displayOrder: Int? = nil
    ) {
        self.completed = completed
        self.reps = reps
        self.load = load
        self.unit = unit
        self.rir = rir
        self.notes = notes
        self.targetReps = targetReps
        self.targetLoad = targetLoad
        self.targetRir = targetRir
        self.displayOrder = displayOrder
    }
}

struct StrengthSetResponse: Codable {
    let id: String
    let completed: Bool?
    let reps: Int?
    let load: Double?
    let unit: String?
    let rir: Int?
    let notes: String?
    let targetReps: String?
    let targetLoad: String?
    let targetRir: String?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let strengthExerciseId: String?
}

// MARK: - Cardio Workouts

struct CardioWorkoutRequest: Codable {
    let name: String
    let modality: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
}

struct CardioWorkoutResponse: Codable {
    let id: String
    let name: String
    let modality: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let exerciseEntryId: String?
    let intervals: [CardioIntervalResponse]?
}

// MARK: - Cardio Intervals

struct CardioIntervalRequest: Codable {
    let completed: Bool?
    let durationSec: Int?
    let distanceM: Int?
    let paceSecPerKm: Int?
    let cadence: Int?
    let strokeRateSpm: Int?
    let powerW: Int?
    let avgHeartRate: Int?
    let avgPowerW: Int?
    let calories: Int?
    let perceivedEffort: Int?
    let notes: String?
    let targetDuration: String?
    let targetDistance: String?
    let targetPace: String?
    let targetCadence: String?
    let targetHeartRate: String?
    let targetPower: String?
    let displayOrder: Int?
    
    init(
        completed: Bool? = nil,
        durationSec: Int? = nil,
        distanceM: Int? = nil,
        paceSecPerKm: Int? = nil,
        cadence: Int? = nil,
        strokeRateSpm: Int? = nil,
        powerW: Int? = nil,
        avgHeartRate: Int? = nil,
        avgPowerW: Int? = nil,
        calories: Int? = nil,
        perceivedEffort: Int? = nil,
        notes: String? = nil,
        targetDuration: String? = nil,
        targetDistance: String? = nil,
        targetPace: String? = nil,
        targetCadence: String? = nil,
        targetHeartRate: String? = nil,
        targetPower: String? = nil,
        displayOrder: Int? = nil
    ) {
        self.completed = completed
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.paceSecPerKm = paceSecPerKm
        self.cadence = cadence
        self.strokeRateSpm = strokeRateSpm
        self.powerW = powerW
        self.avgHeartRate = avgHeartRate
        self.avgPowerW = avgPowerW
        self.calories = calories
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.targetDuration = targetDuration
        self.targetDistance = targetDistance
        self.targetPace = targetPace
        self.targetCadence = targetCadence
        self.targetHeartRate = targetHeartRate
        self.targetPower = targetPower
        self.displayOrder = displayOrder
    }
}

struct CardioIntervalResponse: Codable {
    let id: String
    let completed: Bool?
    let durationSec: Int?
    let distanceM: Int?
    let paceSecPerKm: Int?
    let cadence: Int?
    let strokeRateSpm: Int?
    let powerW: Int?
    let avgHeartRate: Int?
    let avgPowerW: Int?
    let calories: Int?
    let perceivedEffort: Int?
    let notes: String?
    let targetDuration: String?
    let targetDistance: String?
    let targetPace: String?
    let targetCadence: String?
    let targetHeartRate: String?
    let targetPower: String?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let cardioWorkoutId: String?
}

// MARK: - Yoga/Mobility

struct YogaMobilityRequest: Codable {
    let title: String?
    let durationMin: Int?
    let focusAreas: [String]?
    let notes: String?
    let coachNotes: String?
    let targetDuration: String?
    let displayOrder: Int?
    
    init(
        title: String? = nil,
        durationMin: Int? = nil,
        focusAreas: [String]? = nil,
        notes: String? = nil,
        coachNotes: String? = nil,
        targetDuration: String? = nil,
        displayOrder: Int? = nil
    ) {
        self.title = title
        self.durationMin = durationMin
        self.focusAreas = focusAreas
        self.notes = notes
        self.coachNotes = coachNotes
        self.targetDuration = targetDuration
        self.displayOrder = displayOrder
    }
}

struct YogaMobilityResponse: Codable {
    let id: String
    let title: String?
    let durationMin: Int?
    let focusAreas: [String]?
    let notes: String?
    let coachNotes: String?
    let targetDuration: String?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let exerciseEntryId: String?
    let movements: [YogaMovementResponse]?
}

struct YogaMovementRequest: Codable {
    let name: String
    let reps: Int?
    let completed: Bool?
    let displayOrder: Int?
    
    init(name: String, reps: Int? = nil, completed: Bool? = nil, displayOrder: Int? = nil) {
        self.name = name
        self.reps = reps
        self.completed = completed
        self.displayOrder = displayOrder
    }
}

struct YogaMovementResponse: Codable {
    let id: String
    let name: String
    let reps: Int?
    let completed: Bool?
    let displayOrder: Int?
    let createdAt: String?
    let updatedAt: String?
    let yogaMobilityWorkoutId: String?
}

// MARK: - LLM Mapped Data Structures

/// Complete mapped data for a single day, output from LLM mapping
struct MappedDayData: Codable {
    let entry: MappedEntry
    let strengthExercises: [MappedStrengthExercise]?
    let cardioWorkouts: [MappedCardioWorkout]?
    let yogaMobility: MappedYogaMobility?
}

struct MappedEntry: Codable {
    let primaryModality: String?
    let dayNotes: String?
}

struct MappedStrengthExercise: Codable {
    let name: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
    let sets: [MappedStrengthSet]?
}

struct MappedStrengthSet: Codable {
    let completed: Bool?
    let reps: Int?
    let load: Double?
    let unit: String?
    let rir: Int?
    let notes: String?
    let targetReps: String?
    let targetLoad: String?
    let targetRir: String?
    let displayOrder: Int?
    
    /// Convert to API request format
    func toRequest() -> StrengthSetRequest {
        StrengthSetRequest(
            completed: completed,
            reps: reps,
            load: load,
            unit: unit,
            rir: rir,
            notes: notes,
            targetReps: targetReps,
            targetLoad: targetLoad,
            targetRir: targetRir,
            displayOrder: displayOrder
        )
    }
}

struct MappedCardioWorkout: Codable {
    let name: String
    let modality: String
    let notes: String?
    let coachNotes: String?
    let displayOrder: Int?
    let intervals: [MappedCardioInterval]?
}

struct MappedCardioInterval: Codable {
    let completed: Bool?
    let durationSec: Int?
    let distanceM: Int?
    let paceSecPerKm: Int?
    let cadence: Int?
    let strokeRateSpm: Int?
    let powerW: Int?
    let avgHeartRate: Int?
    let avgPowerW: Int?
    let calories: Int?
    let perceivedEffort: Int?
    let notes: String?
    let targetDuration: String?
    let targetDistance: String?
    let targetPace: String?
    let targetCadence: String?
    let targetHeartRate: String?
    let targetPower: String?
    let displayOrder: Int?
    
    /// Convert to API request format
    func toRequest() -> CardioIntervalRequest {
        CardioIntervalRequest(
            completed: completed,
            durationSec: durationSec,
            distanceM: distanceM,
            paceSecPerKm: paceSecPerKm,
            cadence: cadence,
            strokeRateSpm: strokeRateSpm,
            powerW: powerW,
            avgHeartRate: avgHeartRate,
            avgPowerW: avgPowerW,
            calories: calories,
            perceivedEffort: perceivedEffort,
            notes: notes,
            targetDuration: targetDuration,
            targetDistance: targetDistance,
            targetPace: targetPace,
            targetCadence: targetCadence,
            targetHeartRate: targetHeartRate,
            targetPower: targetPower,
            displayOrder: displayOrder
        )
    }
}

struct MappedYogaMobility: Codable {
    let title: String?
    let durationMin: Int?
    let focusAreas: [String]?
    let notes: String?
    let coachNotes: String?
    let targetDuration: String?
    let movements: [MappedYogaMovement]?
    
    /// Convert to API request format
    func toRequest() -> YogaMobilityRequest {
        YogaMobilityRequest(
            title: title,
            durationMin: durationMin,
            focusAreas: focusAreas,
            notes: notes,
            coachNotes: coachNotes,
            targetDuration: targetDuration
        )
    }
}

struct MappedYogaMovement: Codable {
    let name: String
    let reps: Int?
    let completed: Bool?
    let displayOrder: Int?
    
    /// Convert to API request format
    func toRequest() -> YogaMovementRequest {
        YogaMovementRequest(
            name: name,
            reps: reps,
            completed: completed,
            displayOrder: displayOrder
        )
    }
}

// MARK: - Error Types

enum ExerciseAPIError: LocalizedError, CustomStringConvertible {
    case notAuthenticated
    case notFound
    case httpError(Int)
    case invalidResponse
    case encodingError
    case missingCredentials
    case mappingError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Invalid credentials. Check your email and app password in Settings."
        case .notFound:
            return "Resource not found on server."
        case .httpError(let code):
            switch code {
            case 400:
                return "Bad request (HTTP 400). Check the data being sent."
            case 405:
                return "Method not allowed (HTTP 405). The API endpoint may have changed."
            case 500:
                return "Server error (HTTP 500). The server encountered an error."
            default:
                return "Server error (HTTP \(code)). Please try again."
            }
        case .invalidResponse:
            return "Invalid response from server."
        case .encodingError:
            return "Failed to encode request data."
        case .missingCredentials:
            return "Organizer credentials not configured. Set them in Settings."
        case .mappingError(let message):
            return "Data mapping error: \(message)"
        }
    }
    
    var description: String {
        switch self {
        case .notAuthenticated:
            return "notAuthenticated"
        case .notFound:
            return "notFound"
        case .httpError(let code):
            return "httpError(\(code))"
        case .invalidResponse:
            return "invalidResponse"
        case .encodingError:
            return "encodingError"
        case .missingCredentials:
            return "missingCredentials"
        case .mappingError(let message):
            return "mappingError(\(message))"
        }
    }
}
