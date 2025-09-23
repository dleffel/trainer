import Foundation

/// Protocol for all tool executors
protocol ToolExecutor {
    /// List of tool names this executor handles
    var supportedToolNames: [String] { get }

    /// Execute a tool call and return the result
    /// - Parameter toolCall: The parsed tool call detected from the model response
    /// - Returns: A ToolCallResult describing success/failure and payload
    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult
}

/// Registry for managing tool executors
protocol ToolExecutorRegistry {
    /// Register an executor that can handle one or more tool names
    func register(executor: ToolExecutor)

    /// Resolve an executor for a specific tool name
    func executor(for toolName: String) -> ToolExecutor?

    /// All tool names currently supported by the registry
    var allSupportedTools: [String] { get }
}