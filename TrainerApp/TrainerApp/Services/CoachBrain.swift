import Foundation

/// Protocol for testability and dependency injection
protocol CoachBrainProtocol {
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult])
}

/// Pure decision-making engine for the coach
/// This is a stateless service focused only on LLM logic and tool processing
class CoachBrain: CoachBrainProtocol {
    
    // MARK: - Dependencies
    private let toolProcessor: ToolProcessor
    private let systemPromptLoader: SystemPromptLoader.Type
    
    // MARK: - Initialization
    init(
        toolProcessor: ToolProcessor = .shared,
        systemPromptLoader: SystemPromptLoader.Type = SystemPromptLoader.self
    ) {
        self.toolProcessor = toolProcessor
        self.systemPromptLoader = systemPromptLoader
    }
    
    // MARK: - Public Interface
    
    /// Process tool calls in a response
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult]) {
        do {
            let processed = try await toolProcessor.processResponseWithToolCalls(response)
            
            if processed.requiresFollowUp {
                print("🔧 CoachBrain: Executed \(processed.toolResults.count) tools")
                for result in processed.toolResults {
                    print("   ↳ \(result.toolName): \(result.success ? "✅" : "❌")")
                }
            }
            
            return (processed.cleanedResponse, processed.toolResults)
        } catch {
            print("❌ CoachBrain: Tool processing failed: \(error)")
            return (response, [])
        }
    }
}

// MARK: - Mock Implementation for Testing

/// Mock implementation for unit testing
class MockCoachBrain: CoachBrainProtocol {
    var processToolCallsWasCalled = false
    
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult]) {
        processToolCallsWasCalled = true
        return (response, [])
    }
}