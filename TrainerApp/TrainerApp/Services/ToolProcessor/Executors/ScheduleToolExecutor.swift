import Foundation

/// No schedule tools are currently supported per System Prompt
class ScheduleToolExecutor: ToolExecutor {
    var supportedToolNames: [String] { return [] }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        throw ToolError.unknownTool(toolCall.name)
    }
}