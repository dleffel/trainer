import Foundation
import SwiftUI

/// Handles tool calling detection and execution
class ToolProcessor {
    static let shared = ToolProcessor()
    private let parameterParser = ToolParameterParser()
    
    private init() {}
    
    // New modular processor (delegation target)
    private let newProcessor = NewToolProcessor.shared
    
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
        // Delegate to the new modular processor
        return newProcessor.detectToolCalls(in: response)
    }
    
    
    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        // Delegate to the new modular processor
        return try await newProcessor.executeTool(toolCall)
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
    
    
    
    
    
    /// Process a response that may contain tool calls
    /// Returns cleaned response, whether follow-up is needed, and tool results
    func processResponseWithToolCalls(_ response: String) async throws -> ProcessedResponse {
        // Delegate to the new modular processor
        return try await newProcessor.processResponseWithToolCalls(response)
    }
    
    /// Format tool results for inclusion in conversation
    func formatToolResults(_ results: [ToolCallResult]) -> String {
        // Delegate to the new modular processor utilities
        return newProcessor.formatToolResults(results)
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