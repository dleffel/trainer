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
    
    /// Parse workout_json parameters with proper JSON extraction
    private func parseWorkoutJsonParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Use smart parameter parsing for workout_json
        let paramPairs = paramsStr.components(separatedBy: ", ")
        
        for pair in paramPairs {
            if let colonIndex = pair.firstIndex(of: ":") {
                let key = String(pair[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStartIndex = paramsStr.index(after: colonIndex)
                var value = String(pair[valueStartIndex...]).trimmingCharacters(in: .whitespaces)
                
                // Remove surrounding quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                
                // Special handling for workout_json - preserve the entire JSON string
                if key == "workout_json" {
                    if let extractedJson = extractWorkoutJson(from: paramsStr) {
                        parameters["workout_json"] = extractedJson
                    }
                } else {
                    parameters[key] = value
                }
            }
        }
        
        return parameters
    }
    
    /// Extract and parse workout JSON specifically
    private func extractWorkoutJson(from paramsStr: String) -> String? {
        // Find the complete JSON by looking for the opening quote after workout_json:
        guard let workoutJsonRange = paramsStr.range(of: "workout_json:") else {
            return nil
        }
        
        let searchStart = workoutJsonRange.upperBound
        
        // Skip whitespace and find opening quote
        var currentIndex = searchStart
        while currentIndex < paramsStr.endIndex && paramsStr[currentIndex].isWhitespace {
            currentIndex = paramsStr.index(after: currentIndex)
        }
        
        // Skip the opening quote
        if currentIndex < paramsStr.endIndex && paramsStr[currentIndex] == "\"" {
            currentIndex = paramsStr.index(after: currentIndex)
        }
        
        // Find the closing quote, handling escaped quotes
        var jsonEndIndex = currentIndex
        var inEscape = false
        
        while jsonEndIndex < paramsStr.endIndex {
            let char = paramsStr[jsonEndIndex]
            
            if inEscape {
                inEscape = false
            } else if char == "\\" {
                inEscape = true
            } else if char == "\"" {
                // Found the closing quote - check if it's really the end
                let nextIndex = paramsStr.index(after: jsonEndIndex)
                if nextIndex >= paramsStr.endIndex || paramsStr[nextIndex] == "," || paramsStr[nextIndex].isWhitespace {
                    // This is the real closing quote
                    break
                }
            }
            
            jsonEndIndex = paramsStr.index(after: jsonEndIndex)
        }
        
        if jsonEndIndex < paramsStr.endIndex {
            return String(paramsStr[currentIndex..<jsonEndIndex])
        }
        
        return nil
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