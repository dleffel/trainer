import Foundation

/// Handles parsing of tool call parameters from various formats
class ToolParameterParser {
    
    /// Represents different parameter formats that can be parsed
    enum ParameterFormat {
        case simple          // key: value, key: value
        case structured      // JSON-like with complex nested data
        case workoutJson     // Special handling for workout_json parameter
    }
    
    /// Parse parameters from a parameter string, automatically detecting format
    func parseParameters(_ paramsStr: String) -> [String: Any] {
        let trimmedParams = paramsStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let format = detectFormat(trimmedParams)
        
        switch format {
        case .simple:
            return parseSimpleParameters(trimmedParams)
        case .structured, .workoutJson:
            return parseStructuredParameters(trimmedParams)
        }
    }
    
    /// Detect the format of the parameter string
    private func detectFormat(_ paramsStr: String) -> ParameterFormat {
        // Check for JSON-like structures
        if paramsStr.contains("{") || paramsStr.contains("[") {
            return .structured
        }
        
        // Check for workout_json parameter specifically
        if paramsStr.contains("workout_json:") {
            return .workoutJson
        }
        
        // Default to simple key-value format
        return .simple
    }
    
    /// Parse simple key-value parameters (key: value, key: value)
    private func parseSimpleParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        var currentKey = ""
        var currentValue = ""
        var inQuotes = false
        var expectingValue = false
        var escapeNext = false
        
        var i = paramsStr.startIndex
        while i < paramsStr.endIndex {
            let char = paramsStr[i]
            
            if escapeNext {
                currentValue.append(char)
                escapeNext = false
            } else if char == "\\" {
                escapeNext = true
            } else if char == "\"" {
                inQuotes.toggle()
            } else if !inQuotes && char == ":" {
                // Found key-value separator
                currentKey = currentValue.trimmingCharacters(in: .whitespaces)
                currentValue = ""
                expectingValue = true
            } else if !inQuotes && char == "," {
                // Found parameter separator
                if expectingValue && !currentKey.isEmpty {
                    // Remove quotes from value if present
                    var finalValue = currentValue.trimmingCharacters(in: .whitespaces)
                    if finalValue.hasPrefix("\"") && finalValue.hasSuffix("\"") {
                        finalValue = String(finalValue.dropFirst().dropLast())
                    }
                    parameters[currentKey] = finalValue
                }
                currentKey = ""
                currentValue = ""
                expectingValue = false
            } else {
                currentValue.append(char)
            }
            
            i = paramsStr.index(after: i)
        }
        
        // Handle last parameter
        if expectingValue && !currentKey.isEmpty {
            var finalValue = currentValue.trimmingCharacters(in: .whitespaces)
            if finalValue.hasPrefix("\"") && finalValue.hasSuffix("\"") {
                finalValue = String(finalValue.dropFirst().dropLast())
            }
            parameters[currentKey] = finalValue
        }
        
        return parameters
    }
    
    /// Parse structured parameters (JSON-like format) from tool call
    private func parseStructuredParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Handle the workout_json parameter specially since it contains JSON
        if paramsStr.contains("workout_json:") {
            return parseWorkoutJsonParameters(paramsStr)
        } else if paramsStr.contains("workouts:") {
            return parseLegacyWorkoutsParameters(paramsStr)
        } else {
            return parseGenericStructuredParameters(paramsStr)
        }
    }
    
    /// Parse workout_json parameters with robust JSON extraction (quote/escape aware) and simple parsing of other fields
    private func parseWorkoutJsonParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]

        // 1) Extract the workout_json payload first (handles very large, nested JSON with escapes)
        guard let (jsonValue, jsonCloseIndex) = extractWorkoutJsonAndEndIndex(from: paramsStr) else {
            print("❌ ToolParameterParser: workout_json not found or malformed in params (length=\(paramsStr.count))")
            // Fallback to generic parsing to avoid returning empty params entirely
            return parseGenericStructuredParameters(paramsStr)
        }
        parameters["workout_json"] = jsonValue
        print("🧪 ToolParameterParser: Extracted workout_json length=\(jsonValue.count) chars")

        // 2) Parse remaining simple fields (notes/icon/date) from the remainder around the JSON
        // We search the entire string with regex because notes/icon are short and appear outside JSON.
        if let notes = matchQuotedValue(for: "notes", in: paramsStr) {
            parameters["notes"] = notes
            print("🧪 ToolParameterParser: Extracted notes length=\(notes.count)")
        }
        if let icon = matchQuotedValue(for: "icon", in: paramsStr) {
            parameters["icon"] = icon
            print("🧪 ToolParameterParser: Extracted icon='\(icon)'")
        }
        if let date = matchQuotedValue(for: "date", in: paramsStr) {
            parameters["date"] = date
            print("🧪 ToolParameterParser: Extracted date='\(date)'")
        }

        return parameters
    }
    
    /// Extract workout_json value and return it along with the index just after the closing quote
    /// Handles escaped quotes (\") correctly.
    private func extractWorkoutJsonAndEndIndex(from paramsStr: String) -> (String, String.Index)? {
        guard let workoutJsonRange = paramsStr.range(of: "workout_json:") else {
            return nil
        }
        var idx = workoutJsonRange.upperBound

        // Skip whitespace
        while idx < paramsStr.endIndex, paramsStr[idx].isWhitespace {
            idx = paramsStr.index(after: idx)
        }

        // Expect opening quote
        guard idx < paramsStr.endIndex, paramsStr[idx] == "\"" else {
            return nil
        }
        let startContent = paramsStr.index(after: idx) // character after opening quote
        var i = startContent
        var inEscape = false

        while i < paramsStr.endIndex {
            let ch = paramsStr[i]
            if inEscape {
                inEscape = false
            } else if ch == "\\" {
                inEscape = true
            } else if ch == "\"" {
                // closing quote reached
                let jsonValue = String(paramsStr[startContent..<i])
                let afterClosing = paramsStr.index(after: i)
                return (jsonValue, afterClosing)
            }
            i = paramsStr.index(after: i)
        }
        return nil
    }

    /// Match a quoted simple value for a given key (e.g., key: "value"), handling escaped quotes in the value
    private func matchQuotedValue(for key: String, in text: String) -> String? {
        // Regex: key:\s*"((?:[^"\\]|\\.)*)"
        let pattern = "\(key)\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let raw = String(text[valueRange])
        // Unescape common sequences
        return raw
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    
    /// Parse legacy workouts parameters (weekly schedule tool)
    private func parseLegacyWorkoutsParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Extract week_start_date first
        let datePattern = #"week_start_date:\s*"([^"]+)""#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []),
           let dateMatch = dateRegex.firstMatch(in: paramsStr, options: [], range: NSRange(paramsStr.startIndex..., in: paramsStr)) {
            if let dateRange = Range(dateMatch.range(at: 1), in: paramsStr) {
                parameters["week_start_date"] = String(paramsStr[dateRange])
            }
        }
        
        // Extract workouts JSON
        if let workoutsRange = paramsStr.range(of: "workouts:") {
            let startIndex = paramsStr.index(after: workoutsRange.upperBound)
            // Skip whitespace
            var currentIndex = startIndex
            while currentIndex < paramsStr.endIndex && paramsStr[currentIndex].isWhitespace {
                currentIndex = paramsStr.index(after: currentIndex)
            }
            
            // Find the matching closing brace
            if currentIndex < paramsStr.endIndex && paramsStr[currentIndex] == "{" {
                var braceCount = 0
                var endIndex = currentIndex
                
                for i in paramsStr[currentIndex...] {
                    if i == "{" {
                        braceCount += 1
                    } else if i == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            endIndex = paramsStr.index(after: paramsStr.firstIndex(of: i)!)
                            break
                        }
                    }
                }
                
                let workoutsJSON = String(paramsStr[currentIndex..<endIndex])
                
                // Parse the JSON string into a dictionary
                var workouts: [String: String] = [:]
                let lines = workoutsJSON.components(separatedBy: .newlines)
                for line in lines {
                    // Look for patterns like "monday": "workout description"
                    let pattern = #"\"(\w+)\"\s*:\s*\"([^\"]*)\""#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                        if let dayRange = Range(match.range(at: 1), in: line),
                           let workoutRange = Range(match.range(at: 2), in: line) {
                            let day = String(line[dayRange]).lowercased()
                            let workout = String(line[workoutRange])
                            workouts[day] = workout
                        }
                    }
                }
                
                parameters["workouts"] = workouts
            }
        }
        
        return parameters
    }
    
    /// Parse generic structured parameters
    private func parseGenericStructuredParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Simple parameter parsing for other tools
        let paramPairs = paramsStr.split(separator: ",")
        for pair in paramPairs {
            let parts = pair.split(separator: ":")
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                parameters[key] = value
            }
        }
        
        return parameters
    }
}