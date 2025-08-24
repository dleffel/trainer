import Foundation

/// Handles tool calling detection and execution
class ToolProcessor {
    static let shared = ToolProcessor()
    
    private init() {}
    
    /// Pattern to detect tool calls in AI responses
    private let toolCallPattern = #"\[TOOL_CALL:\s*(\w+)(?:\((.*?)\))?\]"#
    
    /// Represents a tool call found in the response
    struct ToolCall {
        let name: String
        let parameters: [String: Any]
        let fullMatch: String
        let range: NSRange
    }
    
    /// Detect tool calls in the AI response
    func detectToolCalls(in response: String) -> [ToolCall] {
        print("🔍 ToolProcessor: Detecting tool calls in response of length \(response.count)")
        print("🔍 ToolProcessor: Pattern: \(toolCallPattern)")
        
        var toolCalls: [ToolCall] = []
        
        guard let regex = try? NSRegularExpression(pattern: toolCallPattern, options: []) else {
            print("❌ ToolProcessor: Failed to create regex")
            return []
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        print("🔍 ToolProcessor: Found \(matches.count) matches")
        
        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: response) {
                let name = String(response[nameRange])
                let parameters: [String: Any] = [:] // For now, get_health_data doesn't need parameters
                
                let toolCall = ToolCall(
                    name: name,
                    parameters: parameters,
                    fullMatch: String(response[Range(match.range, in: response)!]),
                    range: match.range
                )
                toolCalls.append(toolCall)
            }
        }
        
        return toolCalls
    }
    
    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolCall) async throws -> String {
        print("🔧 ToolProcessor: Executing tool '\(toolCall.name)' with parameters: \(toolCall.parameters)")
        
        switch toolCall.name {
        case "get_health_data":
            print("📊 ToolProcessor: Matched get_health_data tool")
            return try await executeGetHealthData()
        default:
            print("❌ ToolProcessor: Unknown tool '\(toolCall.name)'")
            throw ToolError.unknownTool(toolCall.name)
        }
    }
    
    /// Execute the get_health_data tool
    private func executeGetHealthData() async throws -> String {
        print("🏥 ToolProcessor: Starting executeGetHealthData")
        let healthData = try await HealthKitManager.shared.fetchHealthData()
        print("✅ ToolProcessor: Received health data from HealthKitManager")
        
        // Format the health data as a readable string
        var components: [String] = []
        
        if let weight = healthData.weight {
            components.append("Weight: \(String(format: "%.1f", weight)) lb")
        }
        
        if let sleep = healthData.timeAsleepHours {
            components.append("Sleep: \(String(format: "%.1f", sleep)) hours")
        }
        
        if let bodyFat = healthData.bodyFatPercentage {
            components.append("Body Fat: \(String(format: "%.1f", bodyFat))%")
        }
        
        if let leanMass = healthData.leanBodyMass {
            components.append("Lean Body Mass: \(String(format: "%.1f", leanMass)) lb")
        }
        
        if let height = healthData.height {
            let feet = Int(height)
            let inches = Int((height - Double(feet)) * 100)
            components.append("Height: \(feet)'\(inches)\"")
        }
        
        if let age = healthData.age {
            components.append("Age: \(age) years")
        }
        
        if components.isEmpty {
            return "[No health data available]"
        }
        
        return "[Health Data Retrieved: \(components.joined(separator: ", "))]"
    }
    
    /// Process a response that may contain tool calls
    func processResponse(_ response: String) async throws -> String {
        print("🎯 ToolProcessor: Processing response")
        print("🎯 ToolProcessor: Response preview: \(String(response.prefix(200)))...")
        
        let toolCalls = detectToolCalls(in: response)
        
        if toolCalls.isEmpty {
            print("🎯 ToolProcessor: No tool calls found, returning original response")
            return response
        }
        
        print("🎯 ToolProcessor: Found \(toolCalls.count) tool calls")
        
        var processedResponse = response
        
        // Process tool calls in reverse order to maintain string indices
        for toolCall in toolCalls.reversed() {
            do {
                let result = try await executeTool(toolCall)
                
                // Replace the tool call with its result
                if let range = Range(toolCall.range, in: processedResponse) {
                    processedResponse.replaceSubrange(range, with: result)
                }
            } catch {
                // Replace with error message
                if let range = Range(toolCall.range, in: processedResponse) {
                    processedResponse.replaceSubrange(range, with: "[Error executing \(toolCall.name): \(error.localizedDescription)]")
                }
            }
        }
        
        return processedResponse
    }
}

/// Errors related to tool execution
enum ToolError: LocalizedError {
    case unknownTool(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}