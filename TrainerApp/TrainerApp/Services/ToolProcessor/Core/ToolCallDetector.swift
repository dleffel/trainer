import Foundation

/// Handles detection and parsing of tool calls in AI responses
class ToolCallDetector {
    /// Pattern to detect tool calls in AI responses
    private let toolCallPattern = #"\[TOOL_CALL:\s*(\w+)(?:\((.*?)\))?\]"#
    private let parameterParser = ToolParameterParser()

    /// Detect tool calls in the AI response
    /// - Parameter response: The raw model response text that may contain tool calls
    /// - Returns: A list of parsed ToolCall instances in forward order of appearance
    func detectToolCalls(in response: String) -> [ToolProcessor.ToolCall] {
        print("🔍 ToolCallDetector: Detecting tool calls in response of length \(response.count)")

        // Quick diagnostics
        let markers = response.components(separatedBy: "[TOOL_CALL:").count - 1
        print("🔍 ToolCallDetector: Found \(markers) '[TOOL_CALL:' markers (pre-regex)")

        guard let regex = try? NSRegularExpression(
            pattern: toolCallPattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            print("❌ ToolCallDetector: Failed to create regex")
            return []
        }

        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        print("🔍 ToolCallDetector: Regex found \(matches.count) matches")

        var toolCalls: [ToolProcessor.ToolCall] = []
        for (idx, match) in matches.enumerated() {
            print("🔍 ToolCallDetector: Processing match #\(idx + 1)")
            guard let nameRange = Range(match.range(at: 1), in: response) else { continue }
            let name = String(response[nameRange])

            var parameters: [String: Any] = [:]
            if match.numberOfRanges > 2,
               let paramsRange = Range(match.range(at: 2), in: response) {
                let paramsStr = String(response[paramsRange])
                parameters = parameterParser.parseParameters(paramsStr)
            }

            if let fullRange = Range(match.range, in: response) {
                let fullMatch = String(response[fullRange])
                let toolCall = ToolProcessor.ToolCall(
                    name: name,
                    parameters: parameters,
                    fullMatch: fullMatch,
                    range: match.range
                )
                toolCalls.append(toolCall)
            }
        }

        return toolCalls
    }
}