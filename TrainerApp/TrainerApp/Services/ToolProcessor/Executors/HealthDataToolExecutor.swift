import Foundation

/// Executor for health data related tools
class HealthDataToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return ["get_health_data"]
    }

    func executeTool(_ toolCall: ToolProcessor.ToolCall) async throws -> ToolProcessor.ToolCallResult {
        switch toolCall.name {
        case "get_health_data":
            let result = try await executeGetHealthData()
            return ToolProcessor.ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }

    /// Execute the get_health_data tool (migrated from ToolProcessor)
    private func executeGetHealthData() async throws -> String {
        print("🏥 HealthDataToolExecutor: Starting executeGetHealthData")
        let healthData = try await HealthKitManager.shared.fetchHealthData()
        print("✅ HealthDataToolExecutor: Received health data from HealthKitManager")

        // Log the age status for debugging
        if let age = healthData.age {
            print("📊 HealthDataToolExecutor: Age retrieved successfully: \(age) years")
        } else {
            print("⚠️ HealthDataToolExecutor: Age data is nil")
        }

        if let dob = healthData.dateOfBirth {
            print("📅 HealthDataToolExecutor: Date of birth available: \(dob)")
        } else {
            print("⚠️ HealthDataToolExecutor: Date of birth is nil")
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
}