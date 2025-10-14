import Foundation

/// Utility for formatting workout and exercise details for display
/// Extracted from TrainingScheduleManager to promote reusability and testability
struct WorkoutFormatter {
    
    // MARK: - Exercise Formatting
    
    /// Format exercise name from Exercise object
    static func formatExerciseName(_ exercise: Exercise) -> String {
        if let name = exercise.name, !name.isEmpty {
            return name
        }
        
        // Fallback to kind with cleaned up formatting
        let cleanKind = exercise.kind
            .replacingOccurrences(of: "cardio", with: "Cardio - ", options: .caseInsensitive)
            .replacingOccurrences(of: "strength", with: "Strength")
        return cleanKind.isEmpty ? "Exercise" : cleanKind
    }
    
    /// Format exercise details based on type
    static func formatExerciseDetails(_ exercise: Exercise) -> String {
        switch exercise.detail {
        case .strength(let detail):
            return formatStrength(detail)
        case .cardio(let detail):
            return formatCardio(detail)
        case .mobility(let detail):
            return formatMobility(detail)
        case .yoga(let detail):
            return formatYoga(detail)
        case .generic(let detail):
            return formatGeneric(detail)
        }
    }
    
    // MARK: - Type-Specific Exercise Formatters
    
    /// Format strength exercise details
    static func formatStrength(_ detail: StrengthDetail) -> String {
        var parts: [String] = []
        
        if let movement = detail.movement {
            parts.append(movement)
        }
        
        if let sets = detail.sets, !sets.isEmpty {
            parts.append("\(sets.count) sets")
            
            // Show rep scheme if consistent
            let reps = sets.compactMap { $0.reps?.displayValue }
            if !reps.isEmpty {
                let uniqueReps = Set(reps)
                if uniqueReps.count == 1, let rep = uniqueReps.first {
                    parts.append("\(rep) reps")
                } else {
                    parts.append("varied reps")
                }
            }
            
            // Show weight if specified
            if let weight = sets.first?.weight {
                parts.append("@ \(weight)")
            }
            
            // Show tempo if specified
            if let tempo = sets.first?.tempo {
                parts.append("tempo: \(tempo)")
            }
        }
        
        if let superset = detail.superset {
            parts.append("(superset: \(superset))")
        }
        
        return parts.joined(separator: ", ")
    }
    
    /// Format cardio exercise details
    static func formatCardio(_ detail: CardioDetail) -> String {
        var parts: [String] = []
        
        if let modality = detail.modality {
            parts.append(modality)
        }
        
        if let total = detail.total ?? detail.effectiveTotal {
            if let duration = total.durationMinutes {
                parts.append("\(duration) min")
            }
            if let distance = total.distanceMeters {
                parts.append("\(distance)m")
            }
        }
        
        if let segments = detail.segments, !segments.isEmpty {
            parts.append("\(segments.count) intervals")
        }
        
        return parts.isEmpty ? "Cardio workout" : parts.joined(separator: ", ")
    }
    
    /// Format mobility exercise details
    static func formatMobility(_ detail: MobilityDetail) -> String {
        guard let blocks = detail.blocks, !blocks.isEmpty else {
            return "Mobility work"
        }
        
        let blockNames = blocks.map { $0.name }.joined(separator: ", ")
        return "\(blocks.count) movements: \(blockNames)"
    }
    
    /// Format yoga exercise details
    static func formatYoga(_ detail: YogaDetail) -> String {
        guard let blocks = detail.blocks, !blocks.isEmpty else {
            return "Yoga session"
        }
        
        let totalMinutes = blocks.compactMap { $0.durationMinutes }.reduce(0, +)
        return "\(blocks.count) segments, \(totalMinutes) min total"
    }
    
    /// Format generic exercise details
    static func formatGeneric(_ detail: GenericDetail) -> String {
        var parts: [String] = []
        
        if let items = detail.items, !items.isEmpty {
            parts.append(items.joined(separator: ", "))
        }
        
        if let notes = detail.notes {
            parts.append(notes)
        }
        
        return parts.isEmpty ? "Workout" : parts.joined(separator: " - ")
    }
    
    // MARK: - Results Formatting
    
    /// Match results to a specific exercise by name (case-insensitive)
    static func matchResultsToExercise(exerciseName: String, results: [WorkoutSetResult]) -> [WorkoutSetResult] {
        let cleanName = exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return results.filter { result in
            let resultName = result.exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return resultName == cleanName || resultName.contains(cleanName) || cleanName.contains(resultName)
        }
    }
    
    /// Format results for a specific exercise, grouped by set
    static func formatResults(_ results: [WorkoutSetResult], for exerciseName: String) -> String {
        let matchedResults = matchResultsToExercise(exerciseName: exerciseName, results: results)
        return formatResultsForExercise(matchedResults)
    }
    
    /// Format results for a specific exercise (already matched)
    static func formatResultsForExercise(_ results: [WorkoutSetResult]) -> String {
        // Sort by set number, then by timestamp
        let sortedResults = results.sorted { r1, r2 in
            if let s1 = r1.setNumber, let s2 = r2.setNumber {
                return s1 < s2
            }
            return r1.timestamp < r2.timestamp
        }
        
        var formatted = ""
        for result in sortedResults {
            formatted += "     * "
            
            if let setNum = result.setNumber {
                formatted += "Set \(setNum): "
            }
            
            var parts: [String] = []
            
            if let reps = result.reps {
                parts.append("\(reps) reps")
            }
            
            if let loadLb = result.loadLb {
                parts.append("@ \(loadLb) lb")
            } else if let loadKg = result.loadKg {
                parts.append("@ \(loadKg) kg")
            }
            
            if let rir = result.rir {
                parts.append("RIR: \(rir)")
            }
            
            if let rpe = result.rpe {
                parts.append("RPE: \(rpe)")
            }
            
            formatted += parts.joined(separator: ", ")
            
            if let notes = result.notes, !notes.isEmpty {
                formatted += " - \(notes)"
            }
            
            formatted += "\n"
        }
        
        return formatted
    }
    
    /// Format all results without exercise grouping (for legacy workouts)
    static func formatAllResults(_ results: [WorkoutSetResult]) -> String {
        let sortedResults = results.sorted { $0.timestamp < $1.timestamp }
        
        var formatted = ""
        for result in sortedResults {
            formatted += "  - \(result.exerciseName): "
            
            var parts: [String] = []
            
            if let setNum = result.setNumber {
                parts.append("Set \(setNum)")
            }
            
            if let reps = result.reps {
                parts.append("\(reps) reps")
            }
            
            if let loadLb = result.loadLb {
                parts.append("@ \(loadLb) lb")
            } else if let loadKg = result.loadKg {
                parts.append("@ \(loadKg) kg")
            }
            
            if let rir = result.rir {
                parts.append("RIR: \(rir)")
            }
            
            if let rpe = result.rpe {
                parts.append("RPE: \(rpe)")
            }
            
            formatted += parts.joined(separator: ", ")
            formatted += "\n"
        }
        
        return formatted
    }
    
    // MARK: - Date Formatting
    
    /// Format date for display (e.g., "Oct 5, 2025")
    /// Uses UTC timezone for consistent programmatic output across devices/timezones
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")  // Required per .roorules for consistency
        return formatter.string(from: date)
    }
    
    /// Format date and time for display (e.g., "Oct 5, 2025 at 2:57 PM UTC")
    /// Uses UTC timezone for consistent programmatic output across devices/timezones
    static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        formatter.timeZone = TimeZone(identifier: "UTC")  // Consistent with formatDate
        return formatter.string(from: date) + " UTC"  // Explicit timezone in output
    }
}