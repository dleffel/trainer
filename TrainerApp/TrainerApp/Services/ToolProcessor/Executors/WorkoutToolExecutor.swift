import Foundation

/// Executor for workout CRUD operations (structured + legacy)
class WorkoutToolExecutor: ToolExecutor {
    // Dependencies
    private let scheduleManager: TrainingScheduleManager
    private let resultsManager: WorkoutResultsManager
    
    // Dependency injection constructor
    init(scheduleManager: TrainingScheduleManager = TrainingScheduleManager.shared,
         resultsManager: WorkoutResultsManager = WorkoutResultsManager.shared) {
        self.scheduleManager = scheduleManager
        self.resultsManager = resultsManager
    }
    
    // New tool for per-set logging
    // log_set_result(date, exercise, set, reps, load_lb, load_kg, rir, rpe, notes)
    var supportedToolNames: [String] {
        return [
            "plan_workout",
            "update_workout",
            "log_set_result"
        ]
    }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        switch toolCall.name {
        case "plan_workout":
            print("📝 WorkoutToolExecutor: Matched plan_workout tool")
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let workoutJsonParam = toolCall.parameters["workout_json"] as? String
            let notesParam = toolCall.parameters["notes"] as? String
            let iconParam = toolCall.parameters["icon"] as? String

            // Require workout_json for new structured workouts
            guard let workoutJson = workoutJsonParam else {
                return ToolProcessor.ToolCallResult(
                    toolName: toolCall.name,
                    result: "[Error: workout_json parameter is required. Provide structured workout data as JSON.]",
                    success: false
                )
            }

            let result = try await executePlanStructuredWorkout(date: dateParam, workoutJson: workoutJson, notes: notesParam, icon: iconParam)
            let success = !result.hasPrefix("[Error:")
            return ToolProcessor.ToolCallResult(
                toolName: toolCall.name,
                result: result,
                success: success,
                error: success ? nil : result
            )

        case "update_workout":
            print("✏️ WorkoutToolExecutor: Matched update_workout tool")
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let workoutJsonParam = toolCall.parameters["workout_json"] as? String
            let notesParam = toolCall.parameters["notes"] as? String
            let iconParam = toolCall.parameters["icon"] as? String

            // Require workout_json for structured updates
            guard let workoutJson = workoutJsonParam else {
                return ToolProcessor.ToolCallResult(
                    toolName: toolCall.name,
                    result: "[Error: workout_json parameter is required. Provide structured workout data as JSON.]",
                    success: false
                )
            }

            let result = try await executeUpdateStructuredWorkout(date: dateParam, workoutJson: workoutJson, notes: notesParam, icon: iconParam)
            let success = !result.hasPrefix("[Error:")
            return ToolProcessor.ToolCallResult(
                toolName: toolCall.name,
                result: result,
                success: success,
                error: success ? nil : result
            )

        case "log_set_result":
            print("🧾 WorkoutToolExecutor: Matched log_set_result tool")
            // Expected simple params: date, exercise, set, reps, load_lb, load_kg, rir, rpe, notes
            let params = toolCall.parameters

            let dateParam = (params["date"] as? String) ?? "today"

            // Be tolerant to different field names coming from the coach
            // Prefer explicit "exercise", then common aliases
            let exercise = (params["exercise"] as? String)
                ?? (params["exerciseName"] as? String)
                ?? (params["movement"] as? String)
                ?? (params["name"] as? String)
                ?? "Unknown"

            // Accept alternate names for set and reps
            let setStr = (params["set"] as? String)
                ?? (params["set_number"] as? String)
                ?? (params["setIndex"] as? String)

            let repsStr = (params["reps"] as? String)
                ?? (params["rep"] as? String)
                ?? (params["repetitions"] as? String)

            // Accept alternate names for weight units
            let loadLb = (params["load_lb"] as? String)
                ?? (params["weight_lb"] as? String)

            let loadKg = (params["load_kg"] as? String)
                ?? (params["weight_kg"] as? String)

            let rirStr = (params["rir"] as? String)
            let rpeStr = (params["rpe"] as? String)
            let notes = params["notes"] as? String

            let setNumber = setStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let reps = repsStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let rir = rirStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let rpe = rpeStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

            let targetDate = ToolUtilities.parseDate(dateParam)

            let result = await MainActor.run { () -> (success: Bool, error: String?) in
                do {
                    let entry = try WorkoutSetResult(
                        timestamp: Date.current,
                        exerciseName: exercise,
                        setNumber: setNumber,
                        reps: reps,
                        loadLb: loadLb,
                        loadKg: loadKg,
                        rir: rir,
                        rpe: rpe,
                        notes: notes
                    )
                    
                    let success = try resultsManager.appendSetResult(for: targetDate, result: entry)
                    return (success, nil)
                } catch {
                    return (false, error.localizedDescription)
                }
            }

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            let dateKey = dateFmt.string(from: targetDate)

            let response: String
            let success: Bool
            
            if result.success {
                response = "[Set Logged] date=\(dateKey), exercise=\(exercise), set=\(setNumber ?? 0), reps=\(reps ?? 0), load_lb=\(loadLb ?? "-"), load_kg=\(loadKg ?? "-"), rir=\(rir ?? -1), rpe=\(rpe ?? -1)\(notes != nil ? ", notes=\(notes!)" : "")"
                success = true
            } else {
                response = "[Error: \(result.error ?? "Failed to persist set result for \(dateParam)")]"
                success = false
            }

            return ToolProcessor.ToolCallResult(
                toolName: toolCall.name,
                result: response,
                success: success,
                error: success ? nil : response
            )

        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }

    // MARK: - Structured Workouts

    /// Plan a structured workout for a single day
    private func executePlanStructuredWorkout(date: String, workoutJson: String, notes: String?, icon: String?) async throws -> String {
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: === START ===")
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Date parameter = '\(date)'")
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: JSON length = \(workoutJson.count) characters")
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Notes = \(notes ?? "nil")")
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Icon = \(icon ?? "nil")")
        print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Raw JSON (first 300 chars) = \(String(workoutJson.prefix(300)))")

        return await MainActor.run {
            let targetDate = ToolUtilities.parseDate(date)
            print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Parsed target date = \(targetDate)")
            // Compute expected storage key (UTC yyyy-MM-dd) to validate persistence path
            let utcFormatter = DateFormatter()
            utcFormatter.dateFormat = "yyyy-MM-dd"
            utcFormatter.timeZone = TimeZone(identifier: "UTC")
            let storageKey = "workout_\(utcFormatter.string(from: targetDate))"
            print("🔑 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Expected storage key = \(storageKey)")

            // Check if program exists
            guard scheduleManager.programStartDate != nil else {
                print("❌ DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: No program - returning error")
                return "[Error: No training program started. Use start_training_program first]"
            }

            // Unescape the JSON string - remove backslash escapes
            let unescapedJson = workoutJson
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\\\", with: "\\")

            print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Unescaped JSON length = \(unescapedJson.count)")

            // Decode the JSON into StructuredWorkout
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let jsonData = unescapedJson.data(using: .utf8) else {
                print("❌ DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Failed to convert JSON to Data")
                return "[Error: Invalid workout_json format. Could not convert to data.]"
            }

            let structuredWorkout: StructuredWorkout
            do {
                print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Attempting JSON decode...")
                structuredWorkout = try decoder.decode(StructuredWorkout.self, from: jsonData)
                print("✅ DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: JSON decode SUCCESS!")
                print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Workout title = '\(structuredWorkout.title)'")
                print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Exercise count = \(structuredWorkout.exercises.count)")
                let distribution = structuredWorkout.exerciseDistribution
                print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Distribution = cardio:\(distribution.cardio) strength:\(distribution.strength) mobility:\(distribution.mobility) yoga:\(distribution.yoga) generic:\(distribution.generic)")
            } catch {
                print("❌ DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: JSON decode FAILED! \(error)")
                return "[Error: Failed to decode workout_json. \(error.localizedDescription)]"
            }

            // Save the structured workout
            let saveResult = scheduleManager.planStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon)
            print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Save result = \(saveResult)")
            print("🔑 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Persisted under key = \(storageKey)")

            if saveResult {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)

                let distribution = structuredWorkout.exerciseDistribution

                let response = """
                [Structured Workout Planned]
                • Date: \(dateStr)
                • Workout: \(structuredWorkout.displaySummary)
                • Exercises: \(structuredWorkout.exercises.count) (cardio: \(distribution.cardio), strength: \(distribution.strength), mobility: \(distribution.mobility), yoga: \(distribution.yoga))
                \(structuredWorkout.totalDuration != nil ? "• Duration: \(structuredWorkout.totalDuration!) minutes" : "")
                \(notes != nil ? "• Notes: \(notes!)" : "")
                \(icon != nil ? "• Icon: \(icon!)" : "")
                • Link: trainer://calendar/\(dateFormatter.string(from: targetDate).replacingOccurrences(of: " ", with: "-"))
                """
                print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Response = \(response)")
                return response
            } else {
                print("❌ DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Save FAILED")
                return "[Error: Could not save structured workout for \(date)]"
            }
        }
    }

    /// Update an existing structured workout
    private func executeUpdateStructuredWorkout(date: String, workoutJson: String, notes: String?, icon: String?) async throws -> String {
        print("✏️ WorkoutToolExecutor: Updating structured workout for \(date)")

        return await MainActor.run {
            let targetDate = ToolUtilities.parseDate(date)

            // Unescape the JSON string - remove backslash escapes
            let unescapedJson = workoutJson
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\\\", with: "\\")

            print("🔍 DEBUG WorkoutToolExecutor.executeUpdateStructuredWorkout: Unescaped JSON length = \(unescapedJson.count)")

            // Decode the JSON into StructuredWorkout
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let jsonData = unescapedJson.data(using: .utf8) else {
                return "[Error: Invalid workout_json format. Could not convert to data.]"
            }

            let structuredWorkout: StructuredWorkout
            do {
                structuredWorkout = try decoder.decode(StructuredWorkout.self, from: jsonData)
                print("✅ Successfully decoded updated structured workout: \(structuredWorkout.displaySummary)")
            } catch {
                print("❌ JSON decoding failed: \(error)")
                return "[Error: Failed to decode workout_json. \(error.localizedDescription)]"
            }

            // Update the structured workout
            if scheduleManager.updateStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)

                let distribution = structuredWorkout.exerciseDistribution

                return """
                [Structured Workout Updated]
                • Date: \(dateStr)
                • Updated to: \(structuredWorkout.displaySummary)
                • Exercises: \(structuredWorkout.exercises.count) (cardio: \(distribution.cardio), strength: \(distribution.strength), mobility: \(distribution.mobility), yoga: \(distribution.yoga))
                \(notes != nil ? "• Notes: \(notes!)" : "")
                • Link: trainer://calendar/\(dateFormatter.string(from: targetDate).replacingOccurrences(of: " ", with: "-"))
                """
            } else {
                return "[Error: Could not update structured workout for \(date). No existing workout found]"
            }
        }
    }

}