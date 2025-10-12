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
    
    // Universal logging tool for all modalities (strength, cardio, mobility)
    // log_set_result(date, exercise, set, reps, load_lb, rir, interval, time, distance, pace, spm, hr, power, cadence, notes)
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
            let params = toolCall.parameters
            
            // Debug: Log all received parameters
            print("🔍 DEBUG log_set_result parameters: \(params.keys.sorted())")
            
            // STRICT SCHEMA ENFORCEMENT: Required parameter 'exercise'
            guard let exercise = params["exercise"] as? String else {
                // Detect common mistakes and provide helpful error
                var hint = ""
                if params["exerciseName"] != nil {
                    hint = "\n\n❌ You used 'exerciseName' but the correct parameter is 'exercise'"
                } else if params["movement"] != nil {
                    hint = "\n\n❌ You used 'movement' but the correct parameter is 'exercise'"
                } else if params["name"] != nil {
                    hint = "\n\n❌ You used 'name' but the correct parameter is 'exercise'"
                } else {
                    hint = "\n\n💡 Make sure you're using exactly 'exercise' as the parameter name"
                }
                
                return ToolProcessor.ToolCallResult(
                    toolName: toolCall.name,
                    result: "[Error: Missing required parameter 'exercise']\(hint)\n\nCorrect usage:\nlog_set_result(exercise: \"Bench Press\", set: \"1\", reps: \"8\", load_lb: \"185\", rir: \"2\")",
                    success: false
                )
            }
            
            // Extract optional parameters - STRICT NAMES ONLY (no aliases)
            let dateParam = (params["date"] as? String) ?? "today"
            
            // Strength training parameters
            let setStr = params["set"] as? String
            let repsStr = params["reps"] as? String
            let loadLb = params["load_lb"] as? String
            let rirStr = params["rir"] as? String
            
            // Cardio/interval parameters
            let intervalStr = params["interval"] as? String
            let time = params["time"] as? String
            let distance = params["distance"] as? String
            let pace = params["pace"] as? String
            let spmStr = params["spm"] as? String
            let hrStr = params["hr"] as? String
            let powerStr = params["power"] as? String
            let cadenceStr = params["cadence"] as? String
            
            // Universal parameters
            let notes = params["notes"] as? String
            
            // Parse integer values
            let setNumber = setStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let reps = repsStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let rir = rirStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let interval = intervalStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let spm = spmStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let hr = hrStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let power = powerStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let cadence = cadenceStr.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            
            let targetDate = ToolUtilities.parseDate(dateParam)

            let result = await MainActor.run { () -> (success: Bool, error: String?) in
                do {
                    let entry = try WorkoutSetResult(
                        timestamp: Date.current,
                        exerciseName: exercise,
                        setNumber: setNumber,
                        reps: reps,
                        loadLb: loadLb,
                        rir: rir,
                        interval: interval,
                        time: time,
                        distance: distance,
                        pace: pace,
                        spm: spm,
                        hr: hr,
                        power: power,
                        cadence: cadence,
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
                // Build response based on modality (strength vs cardio)
                var parts = ["[Set Logged]", "date=\(dateKey)", "exercise=\(exercise)"]
                
                // Strength fields
                if let s = setNumber { parts.append("set=\(s)") }
                if let r = reps { parts.append("reps=\(r)") }
                if let lb = loadLb { parts.append("load_lb=\(lb)") }
                if let r = rir { parts.append("rir=\(r)") }
                
                // Cardio fields
                if let i = interval { parts.append("interval=\(i)") }
                if let t = time { parts.append("time=\(t)") }
                if let d = distance { parts.append("distance=\(d)") }
                if let p = pace { parts.append("pace=\(p)") }
                if let s = spm { parts.append("spm=\(s)") }
                if let h = hr { parts.append("hr=\(h)") }
                if let p = power { parts.append("power=\(p)W") }
                if let c = cadence { parts.append("cadence=\(c)rpm") }
                
                // Notes
                if let n = notes { parts.append("notes=\(n)") }
                
                response = parts.joined(separator: ", ")
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