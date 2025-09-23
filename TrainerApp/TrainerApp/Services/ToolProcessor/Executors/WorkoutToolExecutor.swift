import Foundation

/// Executor for workout CRUD operations (structured + legacy)
class WorkoutToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return [
            "plan_workout",
            "update_workout",
            "update_workout_legacy",
            "delete_workout"
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

        case "update_workout_legacy":
            print("✏️ WorkoutToolExecutor: Matched update_workout_legacy (string-based) tool")
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let workoutParam = toolCall.parameters["workout"] as? String ?? ""
            let reasonParam = toolCall.parameters["reason"] as? String
            let result = try await executeUpdateWorkout(date: dateParam, workout: workoutParam, reason: reasonParam)
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)

        case "delete_workout":
            print("🗑️ WorkoutToolExecutor: Matched delete_workout tool")
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let reasonParam = toolCall.parameters["reason"] as? String
            let result = try await executeDeleteWorkout(date: dateParam, reason: reasonParam)
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)

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
            let manager = TrainingScheduleManager.shared

            let targetDate = ToolUtilities.parseDate(date)
            print("🔍 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Parsed target date = \(targetDate)")
            // Compute expected storage key (UTC yyyy-MM-dd) to validate persistence path
            let utcFormatter = DateFormatter()
            utcFormatter.dateFormat = "yyyy-MM-dd"
            utcFormatter.timeZone = TimeZone(identifier: "UTC")
            let storageKey = "workout_\(utcFormatter.string(from: targetDate))"
            print("🔑 DEBUG WorkoutToolExecutor.executePlanStructuredWorkout: Expected storage key = \(storageKey)")

            // Check if program exists
            guard manager.programStartDate != nil else {
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
            let saveResult = manager.planStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon)
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
            let manager = TrainingScheduleManager.shared
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
            if manager.updateStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon) {
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

    // MARK: - Legacy (string-based) methods

    /// Plan a single day's workout (LEGACY - for backward compatibility)
    private func executePlanWorkout(date: String, workout: String, notes: String?, icon: String?) async throws -> String {
        print("📝 WorkoutToolExecutor: Planning single workout for \(date) (LEGACY)")
        if let icon = icon {
            print("   with icon: \(icon)")
        }

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = ToolUtilities.parseDate(date)

            // Check if program exists
            guard manager.programStartDate != nil else {
                return "[Error: No training program started. Use start_training_program first]"
            }

            // Call the legacy single-day planning method with icon
            if manager.planSingleWorkout(for: targetDate, workout: workout, notes: notes, icon: icon) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)

                return """
                [Workout Planned]
                • Date: \(dateStr)
                • Workout: \(workout)
                \(notes != nil ? "• Notes: \(notes!)" : "")
                \(icon != nil ? "• Icon: \(icon!)" : "")
                • Status: Saved to calendar
                """
            } else {
                return "[Error: Could not plan workout for \(date)]"
            }
        }
    }

    /// Update an existing workout (legacy)
    private func executeUpdateWorkout(date: String, workout: String, reason: String?) async throws -> String {
        print("✏️ WorkoutToolExecutor: Updating workout for \(date)")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = ToolUtilities.parseDate(date)

            // Get existing workout first
            if let existingDay = manager.getWorkoutDay(for: targetDate) {
                let previousWorkout = existingDay.plannedWorkout ?? "None"

                if manager.updateSingleWorkout(for: targetDate, workout: workout, reason: reason) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "EEEE, MMM d"
                    let dateStr = dateFormatter.string(from: targetDate)

                    return """
                    [Workout Updated]
                    • Date: \(dateStr)
                    • Previous: \(previousWorkout)
                    • Updated to: \(workout)
                    \(reason != nil ? "• Reason: \(reason!)" : "")
                    """
                }
            }

            return "[Error: Could not update workout for \(date). No existing workout found]"
        }
    }

    /// Delete a planned workout
    private func executeDeleteWorkout(date: String, reason: String?) async throws -> String {
        print("🗑️ WorkoutToolExecutor: Deleting workout for \(date)")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = ToolUtilities.parseDate(date)

            if manager.deleteSingleWorkout(for: targetDate, reason: reason) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)

                return """
                [Workout Deleted]
                • Date: \(dateStr)
                \(reason != nil ? "• Reason: \(reason!)" : "")
                • Status: Removed from calendar
                """
            } else {
                return "[Error: Could not delete workout for \(date)]"
            }
        }
    }
}