import Foundation
import SwiftUI

/// Simplified tool processor that coordinates between components
class NewToolProcessor {
    static let shared = NewToolProcessor()

    private let detector: ToolCallDetector
    private let registry: ToolExecutorRegistry
    private let router: ToolCallRouter

    private init() {
        self.detector = ToolCallDetector()
        self.registry = DefaultToolExecutorRegistry()
        self.router = ToolCallRouter(registry: registry)

        // Register all executors
        setupExecutors()
    }

    private func setupExecutors() {
        // Only register tools that are currently mentioned in the system prompt:
        // - get_health_data
        // - plan_workout
        // - update_workout
        registry.register(executor: HealthDataToolExecutor())
        registry.register(executor: WorkoutToolExecutor())
        print("🧭 NewToolProcessor: Executors registered: \(registry.allSupportedTools)")
    }

    /// Detect tool calls in the AI response
    func detectToolCalls(in response: String) -> [ToolProcessor.ToolCall] {
        return detector.detectToolCalls(in: response)
    }

    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        return try await router.executeTool(toolCall)
    }

    /// Process a response that may contain tool calls
    /// Returns cleaned response, whether follow-up is needed, and tool results
    func processResponseWithToolCalls(_ response: String) async throws -> ToolProcessor.ProcessedResponse {
        print("🎯 NewToolProcessor: Processing response")
        let toolCalls = detectToolCalls(in: response)

        if toolCalls.isEmpty {
            return ToolProcessor.ProcessedResponse(
                cleanedResponse: response,
                requiresFollowUp: false,
                toolResults: []
            )
        }

        print("🎯 NewToolProcessor: Found \(toolCalls.count) tool calls")

        var cleanedResponse = response
        var toolResults: [ToolProcessor.ToolCallResult] = []

        // Execute tools in forward order (preserve logical sequence)
        for (index, toolCall) in toolCalls.enumerated() {
            print("🔧 NewToolProcessor: Executing tool \(index + 1)/\(toolCalls.count): \(toolCall.name)")
            let result = try await executeTool(toolCall)
            toolResults.append(result)
        }

        // Remove tool calls from response in reverse order (to maintain string indices)
        for toolCall in toolCalls.reversed() {
            if let range = Range(toolCall.range, in: cleanedResponse) {
                cleanedResponse.replaceSubrange(range, with: "")
            }
        }

        // Clean up any trailing spaces or punctuation before removed tool calls
        cleanedResponse = cleanedResponse
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ToolProcessor.ProcessedResponse(
            cleanedResponse: cleanedResponse,
            requiresFollowUp: true,
            toolResults: toolResults
        )
    }

    /// Format tool results for inclusion in conversation
    func formatToolResults(_ results: [ToolProcessor.ToolCallResult]) -> String {
        return ToolUtilities.formatToolResults(results)
    }
}