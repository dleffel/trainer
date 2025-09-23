import Foundation

/// Default implementation of tool executor registry
class DefaultToolExecutorRegistry: ToolExecutorRegistry {
    private var executorsByTool: [String: ToolExecutor] = [:]

    /// Register an executor that can handle one or more tool names
    func register(executor: ToolExecutor) {
        let names = executor.supportedToolNames
        guard !names.isEmpty else {
            print("⚠️ ToolExecutorRegistry: Attempted to register executor with no supported tools")
            return
        }

        for toolName in names {
            executorsByTool[toolName] = executor
        }
        print("📋 ToolExecutorRegistry: Registered tools: \(names)")
    }

    /// Resolve an executor for a specific tool name
    func executor(for toolName: String) -> ToolExecutor? {
        return executorsByTool[toolName]
    }

    /// All tool names currently supported by the registry
    var allSupportedTools: [String] {
        Array(executorsByTool.keys).sorted()
    }
}