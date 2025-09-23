# ToolProcessor Refactoring Implementation Plan

## Overview
This plan details the step-by-step refactoring of the monolithic 863-line `ToolProcessor.swift` into a modular, maintainable architecture with clear separation of concerns.

## Implementation Strategy

### Phase 1: Foundation & Infrastructure (Low Risk)
Create new supporting files without touching existing functionality.

#### Step 1.1: Create Core Protocols
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Protocols/ToolExecutor.swift`**
```swift
import Foundation

/// Protocol for all tool executors
protocol ToolExecutor {
    /// List of tool names this executor handles
    var supportedToolNames: [String] { get }
    
    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult
}

/// Registry for managing tool executors
protocol ToolExecutorRegistry {
    func register(executor: ToolExecutor)
    func executor(for toolName: String) -> ToolExecutor?
    var allSupportedTools: [String] { get }
}
```

#### Step 1.2: Extract Shared Models
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Models/ToolTypes.swift`**
```swift
import Foundation

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
```

**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Models/ToolError.swift`**
```swift
import Foundation

/// Errors related to tool execution
enum ToolError: LocalizedError {
    case unknownTool(String)
    case executionFailed(String)
    case registrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .registrationFailed(let reason):
            return "Tool registration failed: \(reason)"
        }
    }
}
```

#### Step 1.3: Create Utilities
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Utilities/ToolUtilities.swift`**
```swift
import Foundation

/// Utility functions for tool processing
struct ToolUtilities {
    /// Parse date strings into Date objects
    static func parseDate(_ dateString: String) -> Date {
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
    
    /// Format dates for display
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    /// Format tool results for inclusion in conversation
    static func formatToolResults(_ results: [ToolCallResult]) -> String {
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
```

### Phase 2: Core Infrastructure (Medium Risk)

#### Step 2.1: Create Tool Detection Engine
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Core/ToolCallDetector.swift`**
```swift
import Foundation

/// Handles detection and parsing of tool calls in AI responses
class ToolCallDetector {
    /// Pattern to detect tool calls in AI responses
    private let toolCallPattern = #"\[TOOL_CALL:\s*(\w+)(?:\((.*?)\))?\]"#
    private let parameterParser = ToolParameterParser()
    
    /// Detect tool calls in the AI response
    func detectToolCalls(in response: String) -> [ToolCall] {
        print("🔍 ToolCallDetector: Detecting tool calls in response of length \(response.count)")
        
        // [Move existing detection logic here with improved logging]
        var toolCalls: [ToolCall] = []
        
        guard let regex = try? NSRegularExpression(pattern: toolCallPattern, options: [.dotMatchesLineSeparators]) else {
            print("❌ ToolCallDetector: Failed to create regex")
            return []
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        print("🔍 ToolCallDetector: Found \(matches.count) matches")
        
        for (index, match) in matches.enumerated() {
            if let nameRange = Range(match.range(at: 1), in: response) {
                let name = String(response[nameRange])
                
                var parameters: [String: Any] = [:]
                if match.numberOfRanges > 2,
                   let paramsRange = Range(match.range(at: 2), in: response) {
                    let paramsStr = String(response[paramsRange])
                    parameters = parameterParser.parseParameters(paramsStr)
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
}
```

#### Step 2.2: Create Executor Registry
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Core/ToolExecutorRegistry.swift`**
```swift
import Foundation

/// Default implementation of tool executor registry
class DefaultToolExecutorRegistry: ToolExecutorRegistry {
    private var executors: [String: ToolExecutor] = [:]
    
    func register(executor: ToolExecutor) {
        for toolName in executor.supportedToolNames {
            executors[toolName] = executor
        }
        print("📋 ToolExecutorRegistry: Registered \(executor.supportedToolNames.count) tools: \(executor.supportedToolNames)")
    }
    
    func executor(for toolName: String) -> ToolExecutor? {
        return executors[toolName]
    }
    
    var allSupportedTools: [String] {
        return Array(executors.keys).sorted()
    }
}
```

#### Step 2.3: Create Router
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Core/ToolCallRouter.swift`**
```swift
import Foundation

/// Routes tool calls to appropriate executors
class ToolCallRouter {
    private let registry: ToolExecutorRegistry
    
    init(registry: ToolExecutorRegistry) {
        self.registry = registry
    }
    
    /// Execute a tool call using the appropriate executor
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        print("🔧 ToolCallRouter: Routing tool '\(toolCall.name)'")
        
        guard let executor = registry.executor(for: toolCall.name) else {
            print("❌ ToolCallRouter: No executor found for tool '\(toolCall.name)'")
            throw ToolError.unknownTool(toolCall.name)
        }
        
        do {
            let result = try await executor.executeTool(toolCall)
            print("✅ ToolCallRouter: Tool '\(toolCall.name)' executed successfully")
            return result
        } catch {
            print("❌ ToolCallRouter: Tool '\(toolCall.name)' failed: \(error)")
            return ToolCallResult(
                toolName: toolCall.name,
                result: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }
}
```

### Phase 3: Domain-Specific Executors (Medium Risk)

#### Step 3.1: Health Data Executor
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Executors/HealthDataToolExecutor.swift`**
```swift
import Foundation

/// Executor for health data related tools
class HealthDataToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return ["get_health_data"]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        switch toolCall.name {
        case "get_health_data":
            let result = try await executeGetHealthData()
            return ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }
    
    // [Move existing executeGetHealthData implementation here]
    private func executeGetHealthData() async throws -> String {
        // ... existing implementation
    }
}
```

#### Step 3.2: Training Program Executor
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Executors/TrainingProgramToolExecutor.swift`**
```swift
import Foundation

/// Executor for training program lifecycle tools
class TrainingProgramToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return ["start_training_program"]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        switch toolCall.name {
        case "start_training_program":
            let result = try await executeStartTrainingProgram()
            return ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }
    
    // [Move existing executeStartTrainingProgram implementation here]
    private func executeStartTrainingProgram() async throws -> String {
        // ... existing implementation
    }
}
```

#### Step 3.3: Schedule Executor
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Executors/ScheduleToolExecutor.swift`**
```swift
import Foundation

/// Executor for schedule reading operations
class ScheduleToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return [
            "get_training_status",
            "get_weekly_schedule",
            "get_workout"
        ]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        switch toolCall.name {
        case "get_training_status":
            let result = try await executeGetTrainingStatus()
            return ToolCallResult(toolName: toolCall.name, result: result)
        case "get_weekly_schedule":
            let result = try await executeGetWeeklySchedule()
            return ToolCallResult(toolName: toolCall.name, result: result)
        case "get_workout":
            let dateParam = toolCall.parameters["date"] as? String ?? "today"
            let result = try await executeGetWorkout(date: dateParam)
            return ToolCallResult(toolName: toolCall.name, result: result)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }
    
    // [Move existing implementations here]
    private func executeGetTrainingStatus() async throws -> String { /* ... */ }
    private func executeGetWeeklySchedule() async throws -> String { /* ... */ }
    private func executeGetWorkout(date: String) async throws -> String { /* ... */ }
}
```

#### Step 3.4: Workout Management Executor
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Executors/WorkoutToolExecutor.swift`**
```swift
import Foundation

/// Executor for workout CRUD operations
class WorkoutToolExecutor: ToolExecutor {
    var supportedToolNames: [String] {
        return [
            "plan_workout",
            "update_workout",
            "update_workout_legacy",
            "delete_workout"
        ]
    }
    
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        switch toolCall.name {
        case "plan_workout":
            return try await handlePlanWorkout(toolCall)
        case "update_workout":
            return try await handleUpdateWorkout(toolCall)
        case "update_workout_legacy":
            return try await handleLegacyUpdateWorkout(toolCall)
        case "delete_workout":
            return try await handleDeleteWorkout(toolCall)
        default:
            throw ToolError.unknownTool(toolCall.name)
        }
    }
    
    // [Move all workout-related implementations here]
    private func handlePlanWorkout(_ toolCall: ToolCall) async throws -> ToolCallResult { /* ... */ }
    private func handleUpdateWorkout(_ toolCall: ToolCall) async throws -> ToolCallResult { /* ... */ }
    private func handleLegacyUpdateWorkout(_ toolCall: ToolCall) async throws -> ToolCallResult { /* ... */ }
    private func handleDeleteWorkout(_ toolCall: ToolCall) async throws -> ToolCallResult { /* ... */ }
}
```

### Phase 4: New Simplified Main Processor (High Risk - Requires Testing)

#### Step 4.1: Create New ToolProcessor
**File: `TrainerApp/TrainerApp/Services/ToolProcessor/Core/NewToolProcessor.swift`**
```swift
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
        registry.register(executor: HealthDataToolExecutor())
        registry.register(executor: TrainingProgramToolExecutor())
        registry.register(executor: ScheduleToolExecutor())
        registry.register(executor: WorkoutToolExecutor())
    }
    
    /// Detect tool calls in the AI response
    func detectToolCalls(in response: String) -> [ToolCall] {
        return detector.detectToolCalls(in: response)
    }
    
    /// Execute a tool call and return the result
    func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
        return try await router.executeTool(toolCall)
    }
    
    /// Process a response that may contain tool calls
    func processResponseWithToolCalls(_ response: String) async throws -> ProcessedResponse {
        let toolCalls = detectToolCalls(in: response)
        
        if toolCalls.isEmpty {
            return ProcessedResponse(
                cleanedResponse: response,
                requiresFollowUp: false,
                toolResults: []
            )
        }
        
        var cleanedResponse = response
        var toolResults: [ToolCallResult] = []
        
        // Execute tools in forward order
        for toolCall in toolCalls {
            let result = try await executeTool(toolCall)
            toolResults.append(result)
        }
        
        // Remove tool calls from response in reverse order
        for toolCall in toolCalls.reversed() {
            if let range = Range(toolCall.range, in: cleanedResponse) {
                cleanedResponse.replaceSubrange(range, with: "")
            }
        }
        
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
        return ToolUtilities.formatToolResults(results)
    }
}
```

### Phase 5: Migration & Cutover (High Risk)

#### Step 5.1: Update Original ToolProcessor
Modify the original `ToolProcessor.swift` to delegate to the new implementation:

```swift
// Add to existing ToolProcessor class
private let newProcessor = NewToolProcessor.shared

// Replace existing method implementations with:
func detectToolCalls(in response: String) -> [ToolCall] {
    return newProcessor.detectToolCalls(in: response)
}

func executeTool(_ toolCall: ToolCall) async throws -> ToolCallResult {
    return try await newProcessor.executeTool(toolCall)
}

func processResponseWithToolCalls(_ response: String) async throws -> ProcessedResponse {
    return try await newProcessor.processResponseWithToolCalls(response)
}

func formatToolResults(_ results: [ToolCallResult]) -> String {
    return newProcessor.formatToolResults(results)
}
```

#### Step 5.2: Deprecate Old Implementation
Mark old methods as deprecated and add comments pointing to new structure.

#### Step 5.3: Remove Old Code
After testing, remove the old implementation methods from the original file.

## Risk Mitigation

### Testing Strategy
1. **Unit Tests**: Each executor can be tested independently
2. **Integration Tests**: Test tool routing and execution flows
3. **Regression Tests**: Ensure all existing tool calls continue to work
4. **A/B Testing**: Run both implementations in parallel initially

### Rollback Plan
1. Keep original implementation until fully validated
2. Feature flag to switch between old and new implementations
3. Comprehensive logging to compare results

### Validation Checklist
- [ ] All existing tool calls work identically
- [ ] Performance is equivalent or better
- [ ] Error handling maintains same behavior
- [ ] Logging output is preserved
- [ ] Memory usage doesn't increase significantly

## Implementation Timeline

### Week 1: Foundation (Low Risk)
- Create protocols and shared models
- Extract utilities
- Set up project structure

### Week 2: Core Infrastructure (Medium Risk)
- Implement detector, registry, and router
- Create base executor infrastructure
- Add comprehensive tests

### Week 3: Domain Executors (Medium Risk)
- Migrate health data tools
- Migrate training program tools
- Migrate schedule tools
- Migrate workout tools

### Week 4: Integration & Testing (High Risk)
- Create new main processor
- Set up delegation in original processor
- Comprehensive testing and validation
- Performance benchmarking

### Week 5: Cleanup & Documentation
- Remove deprecated code
- Update documentation
- Final performance validation
- Team knowledge transfer

## Success Metrics

1. **Code Quality**
   - Reduce main ToolProcessor from 863 lines to ~100 lines
   - Each executor should be <200 lines
   - Cyclomatic complexity reduction of 80%

2. **Maintainability**
   - New tool categories can be added without modifying existing code
   - Individual tool changes don't require touching other tools
   - Clear separation of concerns

3. **Testability**
   - 100% unit test coverage for new executors
   - Mock-friendly architecture
   - Isolated testing of individual components

4. **Performance**
   - No performance regression
   - Memory usage remains stable
   - Tool execution time unchanged

## Future Enhancements

Once the refactoring is complete, the new architecture enables:

1. **Dynamic Tool Loading**: Load executors from plugins
2. **Tool Metrics**: Track usage and performance per tool category
3. **Advanced Error Recovery**: Category-specific error handling
4. **Tool Composition**: Chain tools together for complex operations
5. **A/B Testing**: Different executor implementations for experimentation