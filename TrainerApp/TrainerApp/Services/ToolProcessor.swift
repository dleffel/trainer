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
                
                // Parse parameters if present
                var parameters: [String: Any] = [:]
                if match.numberOfRanges > 2,
                   let paramsRange = Range(match.range(at: 2), in: response) {
                    let paramsStr = String(response[paramsRange])
                    // Simple parameter parsing (key:value,key:value format)
                    let paramPairs = paramsStr.split(separator: ",")
                    for pair in paramPairs {
                        let parts = pair.split(separator: ":")
                        if parts.count == 2 {
                            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                            parameters[key] = value
                        }
                    }
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
                
            case "get_workout_plan":
                print("🏋️ ToolProcessor: Matched get_workout_plan tool")
                let dayParam = toolCall.parameters["day"] as? String ?? "today"
                let result = try await executeGetWorkoutPlan(day: dayParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            // Calendar Writing Tools
            case "start_training_program":
                print("🚀 ToolProcessor: Matched start_training_program tool")
                let result = try await executeStartTrainingProgram()
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "create_workout":
                print("📝 ToolProcessor: Matched create_workout tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let typeParam = toolCall.parameters["type"] as? String ?? ""
                let detailsParam = toolCall.parameters["details"] as? String ?? ""
                let result = try await executeCreateWorkout(date: dateParam, type: typeParam, details: detailsParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "mark_workout_complete":
                print("✅ ToolProcessor: Matched mark_workout_complete tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let notesParam = toolCall.parameters["notes"] as? String
                let workoutParam = toolCall.parameters["workout"] as? String
                let result = try await executeMarkWorkoutComplete(date: dateParam, notes: notesParam, workout: workoutParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "plan_week":
                print("📆 ToolProcessor: Matched plan_week tool")
                let weekParam = toolCall.parameters["week"] as? String ?? "current"
                let result = try await executePlanWeek(week: weekParam)
                return ToolCallResult(toolName: toolCall.name, result: result)
                
            case "generate_workout_instructions":
                print("📝 ToolProcessor: Matched generate_workout_instructions tool")
                let dateParam = toolCall.parameters["date"] as? String ?? "today"
                let result = try await executeGenerateWorkoutInstructions(date: dateParam)
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
            
            guard manager.programStartDate != nil else {
                return """
                [Training Status: No program started]
                Use [TOOL_CALL: start_training_program] to begin your 20-week training cycle.
                """
            }
            
            guard let block = manager.currentBlock else {
                return "[Training Status: Program data not available]"
            }
            let week = manager.currentWeek
            let totalWeek = manager.totalWeekInProgram
            let day = manager.currentDay
            
            return """
            [Training Status]
            • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
            • Overall Progress: Week \(totalWeek) of 20
            • Today: \(day.name)
            • Focus: \(getBlockFocus(block.type))
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
                let status = day.completed ? "✅" : "⬜"
                let workout = manager.getDetailedWorkoutPlan(for: day.dayOfWeek)
                
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
            
            let workout = manager.getDetailedWorkoutPlan(for: targetDay)
            let defaultStartDate = Date()
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
            Workout: \(workout)
            """
        }
    }
    
    /// Start a new training program
    private func executeStartTrainingProgram() async throws -> String {
        print("🚀 ToolProcessor: Starting training program")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            if manager.programStartDate != nil {
                manager.restartProgram()
                return """
                [Training Program Restarted]
                • New 20-week cycle started
                • Week 1: Aerobic Capacity Block
                • All previous data cleared
                Your training schedule has been created!
                """
            } else {
                manager.startProgram()
                return """
                [Training Program Started! 🎯]
                20-Week Periodized Rowing Program:
                • Weeks 1-8: Aerobic Capacity
                • Week 9: Deload
                • Weeks 10-19: Hypertrophy-Strength
                • Week 20: Deload/Taper
                
                Your first week's schedule is ready!
                """
            }
        }
    }
    
    /// Create a workout for a specific date
    private func executeCreateWorkout(date: String, type: String, details: String) async throws -> String {
        print("📝 ToolProcessor: Creating workout")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Workout Creation: Start program first with [TOOL_CALL: start_training_program]]"
            }
            
            let targetDate = parseDate(date)
            let dayOfWeek = DayOfWeek.from(date: targetDate)
            
            // Create workout description
            let workoutDescription = type.isEmpty ? details : "\(type): \(details)"
            
            // Find existing day or create new
            if let existingDay = manager.currentWeekDays.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: targetDate)
            }) {
                // Create a new WorkoutDay and update its mutable properties
                var updatedDay = WorkoutDay(
                    date: existingDay.date,
                    blockType: existingDay.blockType
                )
                // Note: plannedWorkout is immutable and auto-calculated
                // We can only update the actual workout and notes
                updatedDay.actualWorkout = workoutDescription
                updatedDay.completed = existingDay.completed
                updatedDay.notes = "Custom workout created: \(workoutDescription)"
                manager.updateWorkoutDay(updatedDay)
            } else {
                var newDay = WorkoutDay(
                    date: targetDate,
                    blockType: manager.currentBlock?.type ?? .aerobicCapacity
                )
                // Note: plannedWorkout is immutable and auto-calculated
                // We set the actual workout instead
                newDay.actualWorkout = workoutDescription
                newDay.notes = "Custom workout created: \(workoutDescription)"
                manager.updateWorkoutDay(newDay)
            }
            
            return """
            [Workout Created]
            • Date: \(formatDate(targetDate))
            • Workout: \(workoutDescription)
            Saved to your training calendar!
            """
        }
    }
    
    /// Mark workout as complete
    private func executeMarkWorkoutComplete(date: String, notes: String?, workout: String? = nil) async throws -> String {
        print("✅ ToolProcessor: Marking workout complete")
        print("📝 ToolProcessor: Workout: \(workout ?? "not specified")")
        print("📝 ToolProcessor: Notes: \(notes ?? "none")")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Workout Tracking: No program started]"
            }
            
            let targetDate = parseDate(date)
            
            guard var workoutDay = manager.currentWeekDays.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: targetDate)
            }) else {
                return "[Workout Tracking: No workout scheduled for this date]"
            }
            
            workoutDay.completed = true
            
            // Store workout details in actualWorkout field
            if let workout = workout {
                workoutDay.actualWorkout = workout
            }
            
            // Store performance notes in notes field
            if let notes = notes {
                workoutDay.notes = notes
            }
            
            manager.updateWorkoutDay(workoutDay)
            
            // Build response message
            var responseLines = [
                "[Workout Completed! ✅]",
                "• Date: \(formatDate(targetDate))",
                "• Day: \(workoutDay.dayOfWeek.name)"
            ]
            
            if let workout = workout {
                responseLines.append("• Workout: \(workout)")
            }
            
            if let notes = notes {
                responseLines.append("• Notes: \(notes)")
            }
            
            responseLines.append("Great job!")
            
            return responseLines.joined(separator: "\n")
        }
    }
    
    /// Plan workouts for a week
    private func executePlanWeek(week: String) async throws -> String {
        print("📆 ToolProcessor: Planning week")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Week Planning: Start program first]"
            }
            
            let targetWeek: Int
            if week == "current" {
                targetWeek = manager.totalWeekInProgram
            } else if week == "next" {
                targetWeek = manager.totalWeekInProgram + 1
            } else if let weekNum = Int(week) {
                targetWeek = weekNum
            } else {
                return "[Week Planning: Invalid week. Use 'current', 'next', or week number]"
            }
            
            guard targetWeek > 0 && targetWeek <= 20 else {
                return "[Week Planning: Week must be between 1 and 20]"
            }
            
            let blockInfo = manager.getBlockForWeek(targetWeek)
            
            var plan: [String] = []
            plan.append("[Week \(targetWeek) Training Plan]")
            plan.append("Block: \(blockInfo.type.rawValue.capitalized) (Week \(blockInfo.weekInBlock))")
            plan.append("")
            
            for day in DayOfWeek.allCases {
                let workout = manager.getDetailedWorkoutPlan(for: day, blockType: blockInfo.type)
                plan.append("• \(day.name): \(workout)")
            }
            
            plan.append("\nWeek planned and saved to calendar!")
            
            return plan.joined(separator: "\n")
        }
    }
    
    /// Generate detailed workout instructions
    private func executeGenerateWorkoutInstructions(date: String) async throws -> String {
        print("📝 ToolProcessor: Generating detailed workout instructions for: \(date)")
        
        return await MainActor.run {
            let manager = TrainingScheduleManager.shared
            
            guard manager.programStartDate != nil else {
                return "[Instructions: No program started. Start your training program first.]"
            }
            
            let targetDate = parseDate(date)
            
            // Find the workout day
            guard let workoutDay = manager.currentWeekDays.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: targetDate)
            }) else {
                return "[Instructions: No workout found for \(formatDate(targetDate))]"
            }
            
            // Generate instructions based on workout type
            let instructions = generateInstructionsForWorkout(workoutDay)
            
            // Update the workout day with instructions
            var updatedDay = workoutDay
            updatedDay.detailedInstructions = instructions
            manager.updateWorkoutDay(updatedDay)
            
            // Return confirmation with deep link
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            let dateString = dateFormatter.string(from: targetDate)
            
            return """
            [Detailed Instructions Generated ✅]
            • Date: \(formatDate(targetDate))
            • Day: \(workoutDay.dayOfWeek.name)
            • Workout: \(workoutDay.plannedWorkout ?? "Custom")
            
            📋 View instructions: trainer://calendar/\(dateString)
            """
        }
    }
    
    /// Generate appropriate instruction sections based on workout type
    private func generateInstructionsForWorkout(_ workoutDay: WorkoutDay) -> WorkoutInstructions {
        var sections: [InstructionSection] = []
        
        // Add sections based on the workout type
        let workoutText = workoutDay.plannedWorkout ?? ""
        
        // Overview section (always included)
        sections.append(InstructionSection(
            type: .overview,
            title: "Today's Session Plan",
            content: [workoutText]
        ))
        
        // For rowing workouts, add HR zones
        if workoutText.contains("RowErg") || workoutText.contains("UT2") || workoutText.contains("AT") {
            sections.append(InstructionSection(
                type: .heartRateZones,
                title: "Heart Rate Zones",
                content: [
                    "UT2/Z1: 106-123 bpm (conversational pace)",
                    "Z2: 123-141 bpm (steady state)",
                    "Race-pace/Z3: 150-162 bpm (threshold)",
                    "Note: Zones based on age 46, HRmax ≈ 176 bpm"
                ]
            ))
        }
        
        // Warm-up section
        if !workoutText.contains("Rest") {
            let warmUp = getWarmUpForWorkout(workoutText)
            sections.append(InstructionSection(
                type: .warmUp,
                title: "Warm-up Protocol",
                content: warmUp
            ))
        }
        
        // Main set details
        if let mainSet = getMainSetDetails(workoutText) {
            sections.append(InstructionSection(
                type: .mainSet,
                title: "Main Set",
                content: mainSet
            ))
        }
        
        // Cool-down section
        if !workoutText.contains("Rest") {
            let coolDown = getCoolDownForWorkout(workoutText)
            sections.append(InstructionSection(
                type: .coolDown,
                title: "Cool-down",
                content: coolDown
            ))
        }
        
        // Hydration reminder
        if workoutText.contains("60′") || workoutText.contains("70-80′") {
            sections.append(InstructionSection(
                type: .hydration,
                title: "Hydration",
                content: [
                    "Sip water every 10 minutes",
                    "Target ~117 fl oz (3.5 L) across the day",
                    "Consider electrolytes for sessions over 60 minutes"
                ]
            ))
        }
        
        // Technique focus for specific workouts
        if let techniqueFocus = getTechniqueFocus(workoutText) {
            sections.append(InstructionSection(
                type: .technique,
                title: "Technique Focus",
                content: techniqueFocus
            ))
        }
        
        // Alternative options
        if let alternatives = getAlternativeOptions(workoutText) {
            sections.append(InstructionSection(
                type: .alternatives,
                title: "Alternative Options",
                content: alternatives
            ))
        }
        
        return WorkoutInstructions(
            generatedAt: Date(),
            sections: sections
        )
    }
    
    private func getWarmUpForWorkout(_ workout: String) -> [String] {
        if workout.contains("RowErg") {
            return [
                "10 minutes progressive rowing (start at 50% effort)",
                "3×30s high-cadence strokes with 60s easy between",
                "Dynamic stretching: hip flexors, hamstrings, shoulders"
            ]
        } else if workout.contains("squat") || workout.contains("Strength") {
            return [
                "5 minutes light cardio (bike or row)",
                "Dynamic mobility: leg swings, hip circles, arm circles",
                "Activation: bodyweight squats, glute bridges",
                "Warm-up sets: 50%, 70%, 85% of working weight"
            ]
        } else if workout.contains("Spin") || workout.contains("bike") {
            return [
                "10 minutes easy spinning",
                "3×30s cadence builds (80→100 rpm)",
                "60s easy spinning between efforts"
            ]
        }
        return ["10 minutes progressive warm-up", "Dynamic stretching as needed"]
    }
    
    private func getMainSetDetails(_ workout: String) -> [String]? {
        if workout.contains("4×10′") {
            return [
                "4 sets of 10 minutes at 85-88% max HR",
                "Stroke rate: 24-26 spm",
                "3 minutes easy recovery between sets",
                "Focus on consistent split times"
            ]
        } else if workout.contains("UT2") {
            return [
                "Continuous rowing at conversational pace",
                "Heart rate: 106-123 bpm (UT2 zone)",
                "Stroke rate: 18-20 spm",
                "Focus on technique and breathing"
            ]
        } else if workout.contains("5×5") || workout.contains("4×6") {
            return [
                "Working sets at 80-85% 1RM",
                "Rest 3-4 minutes between sets",
                "Focus on form over speed",
                "Track weights for progressive overload"
            ]
        }
        return nil
    }
    
    private func getCoolDownForWorkout(_ workout: String) -> [String] {
        if workout.contains("RowErg") || workout.contains("interval") {
            return [
                "5-10 minutes easy rowing",
                "5-8 minutes foam rolling (quads, glutes, T-spine)",
                "Static stretching: hip flexors, hamstrings, shoulders"
            ]
        } else if workout.contains("Strength") || workout.contains("squat") {
            return [
                "5 minutes light cardio",
                "Foam rolling: focus on worked muscle groups",
                "Static stretching: 30s holds for major muscle groups"
            ]
        }
        return ["5-10 minutes easy movement", "Light stretching as needed"]
    }
    
    private func getTechniqueFocus(_ workout: String) -> [String]? {
        if workout.contains("RowErg") {
            return [
                "Smooth, relaxed shoulders",
                "Consistent stroke rhythm",
                "Full body engagement through the drive",
                "Controlled recovery phase"
            ]
        } else if workout.contains("squat") {
            return [
                "Maintain neutral spine",
                "Drive through heels",
                "Knees tracking over toes",
                "Full depth if mobility allows"
            ]
        }
        return nil
    }
    
    private func getAlternativeOptions(_ workout: String) -> [String]? {
        if workout.contains("RowErg") && (workout.contains("60′") || workout.contains("70-80′")) {
            return [
                "Bike: Same duration at equivalent HR zones",
                "Swimming: 40-50 minutes continuous",
                "Cross-trainer: Match time and intensity"
            ]
        } else if workout.contains("RowErg") && workout.contains("interval") {
            return [
                "Bike intervals: Same work:rest ratio",
                "Track running: Adjust distances for impact"
            ]
        }
        return nil
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
    
    // MARK: - Helper Methods
    
    private func getBlockFocus(_ blockType: BlockType) -> String {
        switch blockType {
        case .aerobicCapacity:
            return "Building aerobic base with steady-state and tempo work"
        case .hypertrophyStrength:
            return "Building muscle and strength with intervals and weights"
        case .deload:
            return "Active recovery and adaptation"
        default:
            return "Training progression"
        }
    }
    
    private func parseDate(_ dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            return Date()
        } else if dateString.lowercased() == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateString) ?? Date()
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