import Foundation

/// Routes tool calls to appropriate executors
class ToolCallRouter {
    private let registry: ToolExecutorRegistry

    init(registry: ToolExecutorRegistry) {
        self.registry = registry
    }

    /// Execute a tool call using the appropriate executor
    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        print("🔧 ToolCallRouter: Routing tool '\(toolCall.name)'")

        guard let executor = registry.executor(for: toolCall.name) else {
            print("❌ ToolCallRouter: No executor found for tool '\(toolCall.name)'")
            throw ToolError.unknownTool(toolCall.name)
        }

        do {
            let result = try await executor.executeTool(toolCall)
            print("✅ ToolCallRouter: Tool '\(toolCall.name)' executed successfully")
            return result
        } catch {
            print("❌ ToolCallRouter: Tool '\(toolCall.name)' failed: \(error)")
            return ToolProcessor.ToolCallResult(
                toolName: toolCall.name,
                result: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }
}