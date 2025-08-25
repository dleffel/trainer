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
    
    /// Represents the result of executing a tool
    struct ToolCallResult {
        let toolName: String
        let result: String
        let success: Bool
        let error: String?
        
        init(toolName: String, result: String, success: Bool = true, error: String? = nil) {
            self.toolName = toolName
            self.result = result
            self.success = success
            self.error = error
        }
    }
    
    /// Represents the processed response with tool information
    struct ProcessedResponse {
        let cleanedResponse: String  // Response with tool calls removed
        let requiresFollowUp: Bool   // Whether tool calls were found and executed
        let toolResults: [ToolCallResult]  // Results from tool execution
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
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        print("🔧 ToolProcessor: Executing tool '\(toolCall.name)' with parameters: \(toolCall.parameters)")
        
        do {
            switch toolCall.name {
            case "get_health_data":
                print("📊 ToolProcessor: Matched get_health_data tool")
                let result = try await executeGetHealthData()
                return ToolCallResult(toolName: toolCall.name, result: result)
            default:
                print("❌ ToolProcessor: Unknown tool '\(toolCall.name)'")
                throw ToolError.unknownTool(toolCall.name)
            }
        } catch {
            return ToolCallResult(
                toolName: toolCall.name,
                result: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }
    
    /// Execute the get_health_data tool
    private func executeGetHealthData() async throws -> String {
        print("🏥 ToolProcessor: Starting executeGetHealthData")
        let healthData = try await HealthKitManager.shared.fetchHealthData()
        print("✅ ToolProcessor: Received health data from HealthKitManager")
        
        // Log the age status for debugging
        if let age = healthData.age {
            print("📊 ToolProcessor: Age retrieved successfully: \(age) years")
        } else {
            print("⚠️ ToolProcessor: Age data is nil")
        }
        
        if let dob = healthData.dateOfBirth {
            print("📅 ToolProcessor: Date of birth available: \(dob)")
        } else {
            print("⚠️ ToolProcessor: Date of birth is nil")
        }
        
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
    /// Returns cleaned response, whether follow-up is needed, and tool results
    func processResponseWithToolCalls(_ response: String) async throws -> ProcessedResponse {
        print("🎯 ToolProcessor: Processing response")
        print("🎯 ToolProcessor: Response preview: \(String(response.prefix(200)))...")
        
        let toolCalls = detectToolCalls(in: response)
        
        if toolCalls.isEmpty {
            print("🎯 ToolProcessor: No tool calls found, returning original response")
            return ProcessedResponse(
                cleanedResponse: response,
                requiresFollowUp: false,
                toolResults: []
            )
        }
        
        print("🎯 ToolProcessor: Found \(toolCalls.count) tool calls")
        
        var cleanedResponse = response
        var toolResults: [ToolCallResult] = []
        
        // Process tool calls in reverse order to maintain string indices
        for toolCall in toolCalls.reversed() {
            // Execute the tool
            let result = try await executeTool(toolCall)
            toolResults.insert(result, at: 0) // Insert at beginning to maintain order
            
            // Remove the tool call from the response
            if let range = Range(toolCall.range, in: cleanedResponse) {
                cleanedResponse.replaceSubrange(range, with: "")
            }
        }
        
        // Clean up any trailing spaces or punctuation before removed tool calls
        cleanedResponse = cleanedResponse
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ProcessedResponse(
            cleanedResponse: cleanedResponse,
            requiresFollowUp: true,
            toolResults: toolResults
        )
    }
    
    /// Format tool results for inclusion in conversation
    func formatToolResults(_ results: [ToolCallResult]) -> String {
        var formattedResults: [String] = []
        
        for result in results {
            if result.success {
                formattedResults.append("Tool '\(result.toolName)' executed successfully:\n\(result.result)")
            } else {
                formattedResults.append("Tool '\(result.toolName)' failed: \(result.error ?? "Unknown error")")
            }
        }
        
        return formattedResults.joined(separator: "\n\n")
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