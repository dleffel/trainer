import Foundation

/// No training program tools are currently supported per System Prompt
class TrainingProgramToolExecutor: ToolExecutor {
    var supportedToolNames: [String] { return [] }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        throw ToolError.unknownTool(toolCall.name)
    }
}