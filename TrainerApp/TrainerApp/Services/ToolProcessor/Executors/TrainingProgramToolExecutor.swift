import Foundation

/// Executor for training program lifecycle tools
class TrainingProgramToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return ["start_training_program"]
    }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        switch toolCall.name {
        case "start_training_program":
            let result = try await executeStartTrainingProgram()
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }

    /// Start a new training program (structure only, no workouts) - migrated from ToolProcessor
    private func executeStartTrainingProgram() async throws -> String {
        print("🚀 TrainingProgramToolExecutor: Starting training program structure")

        return await MainActor.run {
            let manager = TrainingScheduleManager.shared

            if manager.programStartDate != nil {
                print("🔍 DEBUG executeStartTrainingProgram - Restarting existing program")
                manager.restartProgram()

                // Debug: Check what block we're actually in after restart
                print("🔍 DEBUG executeStartTrainingProgram - After restart:")
                print("  - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
                print("  - Current week: \(manager.currentWeek)")

                return """
                [Training Program Structure Created]
                • New 20-week cycle initialized
                • Week 1: Hypertrophy-Strength Block
                • All previous data cleared
                • Ready for personalized workout planning

                Use plan_workout to add workouts day by day.
                """
            } else {
                print("🔍 DEBUG executeStartTrainingProgram - Starting fresh program")
                manager.startProgram()

                // Debug: Check what block we're actually in after start
                print("🔍 DEBUG executeStartTrainingProgram - After start:")
                print("  - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
                print("  - Current week: \(manager.currentWeek)")

                return """
                [Training Program Structure Created! 🎯]
                20-Week Periodized Program:
                • Weeks 1-10: Hypertrophy-Strength
                • Week 11: Deload
                • Weeks 12-19: Aerobic Capacity
                • Week 20: Deload/Taper

                Program structure ready. Use plan_workout to add today's workout.
                """
            }
        }
    }
}