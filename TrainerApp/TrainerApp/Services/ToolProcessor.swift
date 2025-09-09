import Foundation
import SwiftUI

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
        
        // Debug: Show first 500 chars to see tool call format
        let preview = String(response.prefix(500))
        print("🔍 ToolProcessor: Response preview:\n\(preview)")
        
        // Debug: Check for TOOL_CALL markers
        let toolCallMarkers = response.components(separatedBy: "[TOOL_CALL:").count - 1
        print("🔍 ToolProcessor: Found \(toolCallMarkers) [TOOL_CALL: markers in response")
        
        // Debug: Try to find plan_week_workouts specifically
        if response.contains("plan_week_workouts") {
            print("✅ ToolProcessor: Response contains 'plan_week_workouts'")
            let range = response.range(of: "plan_week_workouts")!
            let startIndex = response.index(range.lowerBound, offsetBy: -50, limitedBy: response.startIndex) ?? response.startIndex
            let endIndex = response.index(range.upperBound, offsetBy: 200, limitedBy: response.endIndex) ?? response.endIndex
            let context = String(response[startIndex..<endIndex])
            print("🔍 ToolProcessor: Context around plan_week_workouts:\n\(context)")
        }
        
        var toolCalls: [ToolCall] = []
        
        // Try with dotMatchesLineSeparators option for multiline matching
        guard let regex = try? NSRegularExpression(pattern: toolCallPattern, options: [.dotMatchesLineSeparators]) else {
            print("❌ ToolProcessor: Failed to create regex")
            return []
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        print("🔍 ToolProcessor: Regex found \(matches.count) matches (expected: \(toolCallMarkers))")
        
        for (index, match) in matches.enumerated() {
            print("🔍 ToolProcessor: Processing match #\(index + 1)")
            
            if let nameRange = Range(match.range(at: 1), in: response) {
                let name = String(response[nameRange])
                print("🔍 ToolProcessor: Tool name: \(name)")
                
                // Parse parameters if present
                var parameters: [String: Any] = [:]
                if match.numberOfRanges > 2,
                   let paramsRange = Range(match.range(at: 2), in: response) {
                    let paramsStr = String(response[paramsRange])
                    print("🔍 ToolProcessor: Raw parameters for \(name): \(paramsStr.prefix(200))...")
                    
                    // Check if parameters contain JSON
                    let trimmedParams = paramsStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if trimmedParams.contains("{") || trimmedParams.contains("[") {
                        // Parse as JSON-like structure
                        print("🔍 ToolProcessor: Detected JSON parameters, parsing as structured data")
                        parameters = parseStructuredParameters(paramsStr)
                    } else {
                        // Smart parameter parsing that handles quoted strings
                        print("🔍 ToolProcessor: Using smart parameter parsing")
                        parameters = parseSmartParameters(paramsStr)
                    }
                    
                    print("🔍 ToolProcessor: Parsed parameters: \(parameters)")
                }
                
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
    
    /// Parse smart parameters that handle quoted strings
    private func parseSmartParameters(_ paramsStr: String) -> [String: Any] {
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
                    print("🔍 Parsed parameter: \(currentKey) = \(finalValue.prefix(50))...")
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
            print("🔍 Parsed parameter: \(currentKey) = \(finalValue.prefix(50))...")
        }
        
        return parameters
    }
    
    /// Parse structured parameters (JSON-like format) from tool call
    private func parseStructuredParameters(_ paramsStr: String) -> [String: Any] {
        var parameters: [String: Any] = [:]
        
        // Handle the workout_json parameter specially since it contains JSON
        if paramsStr.contains("workout_json:") {
            print("🔍 DEBUG parseStructuredParameters: Found workout_json parameter")
            
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
                        // Find the complete JSON by looking for the opening quote after workout_json:
                        if let workoutJsonRange = paramsStr.range(of: "workout_json:") {
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
                                let workoutJson = String(paramsStr[currentIndex..<jsonEndIndex])
                                parameters["workout_json"] = workoutJson
                                print("🔍 DEBUG parseStructuredParameters: Extracted workout_json length = \(workoutJson.count)")
                            }
                        }
                    } else {
                        parameters[key] = value
                    }
                }
            }
        } else if paramsStr.contains("workouts:") {
            // Legacy handling for the workouts parameter (weekly schedule tool)
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
                    print("📝 Parsed \(workouts.count) workouts from JSON")
                }
            }
        } else {
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
        }
        
        return parameters
    }
    
    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        print("🔧 ToolProcessor: Executing tool '\(toolCall.name)' with parameters: \(toolCall.parameters)")
        
        do {
            switch toolCall.name {
            // Health Data Tools
            case "get_health_data":
                print("📊 ToolProcessor: Matched get_health_data tool")
                let result = try await executeGetHealthData()
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            // Calendar Reading Tools
            case "get_training_status":
                print("📅 ToolProcessor: Matched get_training_status tool")
                let result = try await executeGetTrainingStatus()
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "get_weekly_schedule":
                print("📋 ToolProcessor: Matched get_weekly_schedule tool")
                let result = try await executeGetWeeklySchedule()
                return ToolCallResult(toolName: toolCall.name, result: result)
                
                
            // Calendar Writing Tools
            case "start_training_program":
                print("🚀 ToolProcessor: Matched start_training_program tool")
                let result = try await executeStartTrainingProgram()
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            // Adaptive Planning Tools
            case "plan_workout":
                print("📝 ToolProcessor: Matched plan_workout tool")
                print("🔍 DEBUG plan_workout: All parameters = \(toolCall.parameters)")
                print("🔍 DEBUG plan_workout: Parameter keys = \(Array(toolCall.parameters.keys))")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let workoutJsonParam = toolCall.parameters["workout_json"] as? String
                let notesParam = toolCall.parameters["notes"] as? String
                let iconParam = toolCall.parameters["icon"] as? String
                
                print("🔍 DEBUG plan_workout: dateParam = \(dateParam)")
                print("🔍 DEBUG plan_workout: workoutJsonParam exists = \(workoutJsonParam != nil)")
                print("🔍 DEBUG plan_workout: notesParam = \(notesParam ?? "nil")")
                print("🔍 DEBUG plan_workout: iconParam = \(iconParam ?? "nil")")
                
                // Require workout_json for new structured workouts
                guard let workoutJson = workoutJsonParam else {
                    print("❌ DEBUG plan_workout: workout_json parameter missing or nil")
                    return ToolCallResult(toolName: toolCall.name, result: "[Error: workout_json parameter is required. Provide structured workout data as JSON.]", success: false)
                }
                
                print("✅ DEBUG plan_workout: Found workout_json, length = \(workoutJson.count)")
                
                let result = try await executePlanStructuredWorkout(date: dateParam, workoutJson: workoutJson, notes: notesParam, icon: iconParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "update_workout":
                print("✏️ ToolProcessor: Matched update_workout tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let workoutJsonParam = toolCall.parameters["workout_json"] as? String
                let notesParam = toolCall.parameters["notes"] as? String
                let iconParam = toolCall.parameters["icon"] as? String
                
                // Require workout_json for structured workouts
                guard let workoutJson = workoutJsonParam else {
                    return ToolCallResult(toolName: toolCall.name, result: "[Error: workout_json parameter is required. Provide structured workout data as JSON.]", success: false)
                }
                
                let result = try await executeUpdateStructuredWorkout(date: dateParam, workoutJson: workoutJson, notes: notesParam, icon: iconParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "update_workout_legacy":
                print("✏️ ToolProcessor: Matched update_workout tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let workoutParam = toolCall.parameters["workout"] as? String ?? ""
                let reasonParam = toolCall.parameters["reason"] as? String
                let result = try await executeUpdateWorkout(date: dateParam, workout: workoutParam, reason: reasonParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "delete_workout":
                print("🗑️ ToolProcessor: Matched delete_workout tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let reasonParam = toolCall.parameters["reason"] as? String
                let result = try await executeDeleteWorkout(date: dateParam, reason: reasonParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "get_workout":
                print("🔍 ToolProcessor: Matched get_workout tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let result = try await executeGetWorkout(date: dateParam)
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
    
    // MARK: - Calendar Tool Implementations
    
    /// Get current training status
    private func executeGetTrainingStatus() async throws -> String {
        print("📅 ToolProcessor: Getting training status")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            // DEBUG: Log calendar data availability
            print("🔍 DEBUG executeGetTrainingStatus - Program exists: \(manager.programStartDate != nil)")
            print("🔍 DEBUG executeGetTrainingStatus - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
            print("🔍 DEBUG executeGetTrainingStatus - Workout days count: \(manager.workoutDays.count)")
            
            // Check what's actually stored in the calendar
            let currentWeekDays = manager.generateWeek(containing: Date.current)
            print("🔍 DEBUG executeGetTrainingStatus - Current week has \(currentWeekDays.count) days")
            for (index, day) in currentWeekDays.enumerated() {
                let hasWorkout = day.plannedWorkout != nil
                print("  Day \(index): \(day.dayOfWeek.name) - Has workout: \(hasWorkout)")
                if hasWorkout {
                    print("    Workout preview: \(String(day.plannedWorkout?.prefix(50) ?? ""))")
                }
            }
            
            guard manager.programStartDate != nil else {
                print("⚠️ DEBUG executeGetTrainingStatus - No program started")
                return """
                [Training Status: No program started]
                Use [TOOL_CALL: start_training_program] to begin your 20-week training cycle.
                """
            }
            
            guard let block = manager.currentBlock else {
                print("⚠️ DEBUG executeGetTrainingStatus - No current block")
                return "[Training Status: Program data not available]"
            }
            let week = manager.currentWeek
            let totalWeek = manager.totalWeekInProgram
            let day = manager.currentDay
            
            print("✅ DEBUG executeGetTrainingStatus - Returning status text (not calendar data!)")
            return """
            [Training Status]
            • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
            • Overall Progress: Week \(totalWeek) of 20
            • Today: \(day.name)
            
            Plan a workout appropriate for \(block.type.rawValue) Week \(week).
            """
        }
    }
    
    /// Get weekly training schedule
    private func executeGetWeeklySchedule() async throws -> String {
        print("📋 ToolProcessor: Getting weekly schedule")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Weekly Schedule: No program started. Start your training program first.]"
            }
            
            let weekDays = manager.currentWeekDays
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            
            var schedule: [String] = ["[This Week's Training]"]
            
            for day in weekDays {
                let dateStr = formatter.string(from: day.date)
                let dayName = day.dayOfWeek.name
                let status = "📅"
                let workout = day.plannedWorkout ?? "Workout to be planned"
                
                schedule.append("\(status) \(dayName) (\(dateStr)): \(workout)")
            }
            
            return schedule.joined(separator: "\n")
        }
    }
    
    /// Get workout plan for a specific day
    private func executeGetWorkoutPlan(day: String) async throws -> String {
        print("🏋️ ToolProcessor: Getting workout plan for: \(day)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Workout Plan: No program started]"
            }
            
            let targetDay: DayOfWeek
            if day.lowercased() == "today" {
                targetDay = manager.currentDay
            } else {
                // Try to match day name to DayOfWeek
                let parsedDay: DayOfWeek?
                switch day.lowercased() {
                case "monday": parsedDay = .monday
                case "tuesday": parsedDay = .tuesday
                case "wednesday": parsedDay = .wednesday
                case "thursday": parsedDay = .thursday
                case "friday": parsedDay = .friday
                case "saturday": parsedDay = .saturday
                case "sunday": parsedDay = .sunday
                default: parsedDay = nil
                }
                
                guard let targetDayEnum = parsedDay else {
                    return "[Workout Plan: Invalid day. Use 'today' or weekday name]"
                }
                targetDay = targetDayEnum
            }
            
            // Find today's workout in the current week
            let todayWorkout = manager.currentWeekDays.first {
                $0.dayOfWeek == targetDay
            }?.plannedWorkout ?? "Workout not yet planned. Use plan_week_workouts to add workouts."
            
            let defaultStartDate = Date.current
            let defaultEndDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: defaultStartDate) ?? defaultStartDate
            let block = manager.currentBlock ?? TrainingBlock(
                type: .aerobicCapacity,
                startDate: defaultStartDate,
                endDate: defaultEndDate,
                weekNumber: 1
            )
            
            return """
            [Workout Plan - \(targetDay.name)]
            Block: \(block.type.rawValue.capitalized)
            Workout: \(todayWorkout)
            """
        }
    }
    
    /// Start a new training program (structure only, no workouts)
    private func executeStartTrainingProgram() async throws -> String {
        print("🚀 ToolProcessor: Starting training program structure")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            if manager.programStartDate != nil {
                print("🔍 DEBUG executeStartTrainingProgram - Restarting existing program")
                manager.restartProgram()
                
                // Debug: Check what block we're actually in after restart
                print("🔍 DEBUG executeStartTrainingProgram - After restart:")
                print("  - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
                print("  - Current week: \(manager.currentWeek)")
                
                return """
                [Training Program Structure Created]
                • New 20-week cycle initialized
                • Week 1: Hypertrophy-Strength Block
                • All previous data cleared
                • Ready for personalized workout planning
                
                Use plan_workout to add workouts day by day.
                """
            } else {
                print("🔍 DEBUG executeStartTrainingProgram - Starting fresh program")
                manager.startProgram()
                
                // Debug: Check what block we're actually in after start
                print("🔍 DEBUG executeStartTrainingProgram - After start:")
                print("  - Current block: \(manager.currentBlock?.type.rawValue ?? "nil")")
                print("  - Current week: \(manager.currentWeek)")
                
                return """
                [Training Program Structure Created! 🎯]
                20-Week Periodized Program:
                • Weeks 1-10: Hypertrophy-Strength
                • Week 11: Deload
                • Weeks 12-19: Aerobic Capacity
                • Week 20: Deload/Taper
                
                Program structure ready. Use plan_workout to add today's workout.
                """
            }
        }
    }
    // MARK: - New Adaptive Planning Tool Implementations
    
    /// Plan a structured workout for a single day
    private func executePlanStructuredWorkout(date: String, workoutJson: String, notes: String?, icon: String?) async throws -> String {
        print("🔍 DEBUG executePlanStructuredWorkout: === STARTING EXECUTION ===")
        print("🔍 DEBUG executePlanStructuredWorkout: Date parameter = '\(date)'")
        print("🔍 DEBUG executePlanStructuredWorkout: JSON length = \(workoutJson.count) characters")
        print("🔍 DEBUG executePlanStructuredWorkout: Notes = \(notes ?? "nil")")
        print("🔍 DEBUG executePlanStructuredWorkout: Icon = \(icon ?? "nil")")
        print("🔍 DEBUG executePlanStructuredWorkout: Raw JSON (first 300 chars) = \(String(workoutJson.prefix(300)))")
        
        return await MainActor.run {
            print("🔍 DEBUG executePlanStructuredWorkout: Entered MainActor.run")
            let manager = TrainingScheduleManager.shared
            print("🔍 DEBUG executePlanStructuredWorkout: Got TrainingScheduleManager.shared")
            
            let targetDate = parseDate(date)
            print("🔍 DEBUG executePlanStructuredWorkout: Parsed target date = \(targetDate)")
            
            // Check if program exists
            let hasProgram = manager.programStartDate != nil
            print("🔍 DEBUG executePlanStructuredWorkout: Program exists = \(hasProgram)")
            guard hasProgram else {
                print("❌ DEBUG executePlanStructuredWorkout: No program - returning error")
                return "[Error: No training program started. Use start_training_program first]"
            }
            
            // Unescape the JSON string - remove backslash escapes
            print("🔍 DEBUG executePlanStructuredWorkout: Starting JSON unescaping")
            let unescapedJson = workoutJson
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\\\", with: "\\")
            
            print("🔍 DEBUG executePlanStructuredWorkout: Unescaped JSON length = \(unescapedJson.count)")
            print("🔍 DEBUG executePlanStructuredWorkout: Unescaped JSON (first 300 chars) = \(String(unescapedJson.prefix(300)))")
            
            // Decode the JSON into StructuredWorkout
            print("🔍 DEBUG executePlanStructuredWorkout: Creating JSON decoder")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            guard let jsonData = unescapedJson.data(using: .utf8) else {
                print("❌ DEBUG executePlanStructuredWorkout: Failed to convert JSON to Data")
                return "[Error: Invalid workout_json format. Could not convert to data.]"
            }
            print("🔍 DEBUG executePlanStructuredWorkout: JSON converted to Data, size = \(jsonData.count) bytes")
            
            let structuredWorkout: StructuredWorkout
            do {
                print("🔍 DEBUG executePlanStructuredWorkout: Attempting JSON decode...")
                structuredWorkout = try decoder.decode(StructuredWorkout.self, from: jsonData)
                print("✅ DEBUG executePlanStructuredWorkout: JSON decode SUCCESS!")
                print("🔍 DEBUG executePlanStructuredWorkout: Workout title = '\(structuredWorkout.title)'")
                print("🔍 DEBUG executePlanStructuredWorkout: Exercise count = \(structuredWorkout.exercises.count)")
                let distribution = structuredWorkout.exerciseDistribution
                print("🔍 DEBUG executePlanStructuredWorkout: Distribution = cardio:\(distribution.cardio) strength:\(distribution.strength) mobility:\(distribution.mobility) yoga:\(distribution.yoga) generic:\(distribution.generic)")
            } catch {
                print("❌ DEBUG executePlanStructuredWorkout: JSON decode FAILED!")
                print("❌ DEBUG executePlanStructuredWorkout: Error = \(error)")
                print("❌ DEBUG executePlanStructuredWorkout: Localized description = \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    print("❌ DEBUG executePlanStructuredWorkout: DecodingError details = \(decodingError)")
                }
                return "[Error: Failed to decode workout_json. \(error.localizedDescription)]"
            }
            
            // Save the structured workout
            print("🔍 DEBUG executePlanStructuredWorkout: Calling manager.planStructuredWorkout...")
            print("🔍 DEBUG executePlanStructuredWorkout: Target date = \(targetDate)")
            print("🔍 DEBUG executePlanStructuredWorkout: Workout title = '\(structuredWorkout.title)'")
            let saveResult = manager.planStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon)
            print("🔍 DEBUG executePlanStructuredWorkout: Save result = \(saveResult)")
            
            if saveResult {
                print("✅ DEBUG executePlanStructuredWorkout: Save SUCCESS - creating response")
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)
                
                let distribution = structuredWorkout.exerciseDistribution
                
                let response = """
                [Structured Workout Planned]
                • Date: \(dateStr)
                • Workout: \(structuredWorkout.displaySummary)
                • Exercises: \(structuredWorkout.exercises.count) (cardio: \(distribution.cardio), strength: \(distribution.strength), mobility: \(distribution.mobility), yoga: \(distribution.yoga))
                \(structuredWorkout.totalDuration != nil ? "• Duration: \(structuredWorkout.totalDuration!) minutes" : "")
                \(notes != nil ? "• Notes: \(notes!)" : "")
                \(icon != nil ? "• Icon: \(icon!)" : "")
                • Link: trainer://calendar/\(dateFormatter.string(from: targetDate).replacingOccurrences(of: " ", with: "-"))
                """
                print("🔍 DEBUG executePlanStructuredWorkout: Response = \(response)")
                return response
            } else {
                print("❌ DEBUG executePlanStructuredWorkout: Save FAILED")
                return "[Error: Could not save structured workout for \(date)]"
            }
        }
    }
    
    /// Update an existing structured workout
    private func executeUpdateStructuredWorkout(date: String, workoutJson: String, notes: String?, icon: String?) async throws -> String {
        print("✏️ ToolProcessor: Updating structured workout for \(date)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = parseDate(date)
            
            // Unescape the JSON string - remove backslash escapes
            let unescapedJson = workoutJson
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\\\", with: "\\")
            
            print("🔍 DEBUG executeUpdateStructuredWorkout: Unescaped JSON length = \(unescapedJson.count)")
            
            // Decode the JSON into StructuredWorkout
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            guard let jsonData = unescapedJson.data(using: .utf8) else {
                return "[Error: Invalid workout_json format. Could not convert to data.]"
            }
            
            let structuredWorkout: StructuredWorkout
            do {
                structuredWorkout = try decoder.decode(StructuredWorkout.self, from: jsonData)
                print("✅ Successfully decoded updated structured workout: \(structuredWorkout.displaySummary)")
            } catch {
                print("❌ JSON decoding failed: \(error)")
                return "[Error: Failed to decode workout_json. \(error.localizedDescription)]"
            }
            
            // Update the structured workout
            if manager.updateStructuredWorkout(for: targetDate, structuredWorkout: structuredWorkout, notes: notes, icon: icon) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)
                
                let distribution = structuredWorkout.exerciseDistribution
                
                return """
                [Structured Workout Updated]
                • Date: \(dateStr)
                • Updated to: \(structuredWorkout.displaySummary)
                • Exercises: \(structuredWorkout.exercises.count) (cardio: \(distribution.cardio), strength: \(distribution.strength), mobility: \(distribution.mobility), yoga: \(distribution.yoga))
                \(notes != nil ? "• Notes: \(notes!)" : "")
                • Link: trainer://calendar/\(dateFormatter.string(from: targetDate).replacingOccurrences(of: " ", with: "-"))
                """
            } else {
                return "[Error: Could not update structured workout for \(date). No existing workout found]"
            }
        }
    }
    
    /// Plan a single day's workout (LEGACY - for backward compatibility)
    private func executePlanWorkout(date: String, workout: String, notes: String?, icon: String?) async throws -> String {
        print("📝 ToolProcessor: Planning single workout for \(date) (LEGACY)")
        if let icon = icon {
            print("   with icon: \(icon)")
        }
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = parseDate(date)
            
            // Check if program exists
            guard manager.programStartDate != nil else {
                return "[Error: No training program started. Use start_training_program first]"
            }
            
            // Call the legacy single-day planning method with icon
            if manager.planSingleWorkout(for: targetDate, workout: workout, notes: notes, icon: icon) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)
                
                return """
                [Workout Planned]
                • Date: \(dateStr)
                • Workout: \(workout)
                \(notes != nil ? "• Notes: \(notes!)" : "")
                \(icon != nil ? "• Icon: \(icon!)" : "")
                • Status: Saved to calendar
                """
            } else {
                return "[Error: Could not plan workout for \(date)]"
            }
        }
    }
    
    /// Update an existing workout
    private func executeUpdateWorkout(date: String, workout: String, reason: String?) async throws -> String {
        print("✏️ ToolProcessor: Updating workout for \(date)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = parseDate(date)
            
            // Get existing workout first
            if let existingDay = manager.getWorkoutDay(for: targetDate) {
                let previousWorkout = existingDay.plannedWorkout ?? "None"
                
                if manager.updateSingleWorkout(for: targetDate, workout: workout, reason: reason) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "EEEE, MMM d"
                    let dateStr = dateFormatter.string(from: targetDate)
                    
                    return """
                    [Workout Updated]
                    • Date: \(dateStr)
                    • Previous: \(previousWorkout)
                    • Updated to: \(workout)
                    \(reason != nil ? "• Reason: \(reason!)" : "")
                    """
                }
            }
            
            return "[Error: Could not update workout for \(date). No existing workout found]"
        }
    }
    
    /// Delete a planned workout
    private func executeDeleteWorkout(date: String, reason: String?) async throws -> String {
        print("🗑️ ToolProcessor: Deleting workout for \(date)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = parseDate(date)
            
            if manager.deleteSingleWorkout(for: targetDate, reason: reason) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)
                
                return """
                [Workout Deleted]
                • Date: \(dateStr)
                \(reason != nil ? "• Reason: \(reason!)" : "")
                • Status: Removed from calendar
                """
            } else {
                return "[Error: Could not delete workout for \(date)]"
            }
        }
    }
    
    /// Get a specific day's workout
    private func executeGetWorkout(date: String) async throws -> String {
        print("🔍 ToolProcessor: Getting workout for \(date)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            let targetDate = parseDate(date)
            
            if let workoutDay = manager.getWorkoutDay(for: targetDate) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let dateStr = dateFormatter.string(from: targetDate)
                
                if let plannedWorkout = workoutDay.plannedWorkout {
                    return """
                    [Workout for \(dateStr)]
                    • Block: \(workoutDay.blockType.rawValue.capitalized)
                    • Planned: \(plannedWorkout)
                    """
                } else {
                    return """
                    [No Workout Planned]
                    • Date: \(dateStr)
                    • Block: \(workoutDay.blockType.rawValue.capitalized)
                    • Status: No workout scheduled for this day
                    """
                }
            } else {
                return "[Error: Could not find workout for \(date)]"
            }
        }
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
        
        // CRITICAL FIX: Execute tools in FORWARD order (preserve logical sequence)
        print("🔧 ToolProcessor: Executing tools in forward order...")
        for (index, toolCall) in toolCalls.enumerated() {
            print("🔧 ToolProcessor: Executing tool \(index + 1)/\(toolCalls.count): \(toolCall.name)")
            // Execute the tool
            let result = try await executeTool(toolCall)
            toolResults.append(result) // Add to end to maintain order
        }
        
        // Remove tool calls from response in REVERSE order (to maintain string indices)
        print("🧹 ToolProcessor: Removing tool calls from response in reverse order...")
        for toolCall in toolCalls.reversed() {
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
    
    // MARK: - Helper Methods
    
    private func parseDate(_ dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            return Date.current
        } else if dateString.lowercased() == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date.current)!
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateString) ?? Date.current
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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