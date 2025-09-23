import Foundation

/// Executor for schedule reading operations
class ScheduleToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return [
            "get_training_status",
            "get_weekly_schedule",
            "get_workout"
        ]
    }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        switch toolCall.name {
        case "get_training_status":
            let result = try await executeGetTrainingStatus()
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)
        case "get_weekly_schedule":
            let result = try await executeGetWeeklySchedule()
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)
        case "get_workout":
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let result = try await executeGetWorkout(date: dateParam)
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }

    /// Get current training status (migrated from ToolProcessor)
    private func executeGetTrainingStatus() async throws -> String {
        print("📅 ScheduleToolExecutor: Getting training status")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared

            // DEBUG: Log calendar data availability
            print("🔍 DEBUG executeGetTrainingStatus - Program exists: \(manager.programStartDate != nil)")
            print("🔍 DEBUG executeGetTrainingStatus - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
            print("🔍 DEBUG executeGetTrainingStatus - Workout days count: \(manager.workoutDays.count)")

            // Check what's actually stored in the calendar
            let currentWeekDays = manager.generateWeek(containing: Date.current)
            print("🔍 DEBUG executeGetTrainingStatus - Current week has \(currentWeekDays.count) days")
            for (index, day) in currentWeekDays.enumerated() {
                let hasWorkout = day.plannedWorkout != nil
                print("  Day \(index): \(day.dayOfWeek.name) - Has workout: \(hasWorkout)")
                if hasWorkout {
                    print("    Workout preview: \(String(day.plannedWorkout?.prefix(50) ?? ""))")
                }
            }

            guard manager.programStartDate != nil else {
                print("⚠️ DEBUG executeGetTrainingStatus - No program started")
                return """
                [Training Status: No program started]
                Use [TOOL_CALL: start_training_program] to begin your 20-week training cycle.
                """
            }

            guard let block = manager.currentBlock else {
                print("⚠️ DEBUG executeGetTrainingStatus - No current block")
                return "[Training Status: Program data not available]"
            }
            let week = manager.currentWeek
            let totalWeek = manager.totalWeekInProgram
            let day = manager.currentDay

            print("✅ DEBUG executeGetTrainingStatus - Returning status text (not calendar data!)")
            return """
            [Training Status]
            • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
            • Overall Progress: Week \(totalWeek) of 20
            • Today: \(day.name)

            Plan a workout appropriate for \(block.type.rawValue) Week \(week).
            """
        }
    }

    /// Get weekly training schedule (migrated from ToolProcessor)
    private func executeGetWeeklySchedule() async throws -> String {
        print("📋 ScheduleToolExecutor: Getting weekly schedule")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared

            guard manager.programStartDate != nil else {
                return "[Weekly Schedule: No program started. Start your training program first.]"
            }

            let weekDays = manager.currentWeekDays
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"

            var schedule: [String] = ["[This Week's Training]"]

            for day in weekDays {
                let dateStr = formatter.string(from: day.date)
                let dayName = day.dayOfWeek.name
                let status = "📅"
                let workout = day.plannedWorkout ?? "Workout to be planned"

                schedule.append("\(status) \(dayName) (\(dateStr)): \(workout)")
            }

            return schedule.joined(separator: "\n")
        }
    }

    /// Get a specific day's workout (migrated from ToolProcessor)
    private func executeGetWorkout(date: String) async throws -> String {
        print("🔍 ScheduleToolExecutor: Getting workout for \(date)")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = ToolUtilities.parseDate(date)

            if let workoutDay = manager.getWorkoutDay(for: targetDate) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)

                if let plannedWorkout = workoutDay.plannedWorkout {
                    return """
                    [Workout for \(dateStr)]
                    • Block: \(workoutDay.blockType.rawValue.capitalized)
                    • Planned: \(plannedWorkout)
                    """
                } else {
                    return """
                    [No Workout Planned]
                    • Date: \(dateStr)
                    • Block: \(workoutDay.blockType.rawValue.capitalized)
                    • Status: No workout scheduled for this day
                    """
                }
            } else {
                return "[Error: Could not find workout for \(date)]"
            }
        }
    }
}