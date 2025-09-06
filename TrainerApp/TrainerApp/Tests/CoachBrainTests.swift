import XCTest
@testable import TrainerApp

/// Unit tests demonstrating the improved testability of the refactored CoachBrain
class CoachBrainTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var sut: CoachBrain!
    var mockToolProcessor: MockToolProcessor!
    
    override func setUp() {
        super.setUp()
        mockToolProcessor = MockToolProcessor()
        sut = CoachBrain(toolProcessor: mockToolProcessor)
    }
    
    override func tearDown() {
        sut = nil
        mockToolProcessor = nil
        super.tearDown()
    }
    
    // MARK: - Context Evaluation Tests
    
    func testEvaluateContext_NoAPIKey_ReturnsSetupMessage() async throws {
        // Given
        UserDefaults.standard.removeObject(forKey: "OPENROUTER_API_KEY")
        let context = createTestContext(programExists: false)
        
        // When
        let decision = try await sut.evaluateContext(context)
        
        // Then
        XCTAssertTrue(decision.shouldSendMessage)
        XCTAssertEqual(decision.message, "Ready to start your rowing journey? Open the app to add your API key and begin!")
        XCTAssertEqual(decision.reasoning, "No API key configured - guiding user to complete setup")
    }
    
    func testEvaluateContext_NoProgramExists_InitializesProgram() async throws {
        // Given
        setMockAPIKey()
        let context = createTestContext(programExists: false)
        
        // Configure mock to return program setup tool calls
        mockToolProcessor.mockToolCalls = [
            ToolCall(name: "start_training_program", parameters: [:], fullMatch: "", range: NSRange())
        ]
        
        // When
        let decision = try await sut.evaluateContext(context)
        
        // Then
        XCTAssertTrue(mockToolProcessor.processResponseCalled)
        XCTAssertEqual(mockToolProcessor.processedToolCalls.count, 1)
        XCTAssertEqual(mockToolProcessor.processedToolCalls.first?.name, "start_training_program")
    }
    
    func testEvaluateContext_ExistingProgram_ChecksWorkoutStatus() async throws {
        // Given
        setMockAPIKey()
        let context = createTestContext(
            programExists: true,
            todaysWorkout: "60min Steady State"
        )
        
        // When
        let decision = try await sut.evaluateContext(context)
        
        // Then
        XCTAssertTrue(mockToolProcessor.processResponseCalled)
        // Verify context was properly evaluated
    }
    
    // MARK: - Tool Processing Tests
    
    func testProcessToolCalls_SingleTool_ExecutesSuccessfully() async throws {
        // Given
        let response = "Let me check your status [TOOL_CALL: get_training_status]"
        mockToolProcessor.mockProcessedResponse = ProcessedResponse(
            cleanedResponse: "Let me check your status",
            requiresFollowUp: true,
            toolResults: [
                ToolCallResult(
                    toolName: "get_training_status",
                    result: "[Training Status: Week 3 of Aerobic Block]"
                )
            ]
        )
        
        // When
        let (processed, results) = try await sut.processToolCalls(in: response)
        
        // Then
        XCTAssertEqual(processed, "Let me check your status")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.toolName, "get_training_status")
    }
    
    func testProcessToolCalls_NoTools_ReturnsOriginalResponse() async throws {
        // Given
        let response = "Great job on today's workout!"
        mockToolProcessor.mockProcessedResponse = ProcessedResponse(
            cleanedResponse: response,
            requiresFollowUp: false,
            toolResults: []
        )
        
        // When
        let (processed, results) = try await sut.processToolCalls(in: response)
        
        // Then
        XCTAssertEqual(processed, response)
        XCTAssertTrue(results.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    private func createTestContext(
        programExists: Bool = true,
        todaysWorkout: String? = nil
    ) -> CoachContext {
        return CoachContext(
            currentTime: Date(),
            dayOfWeek: "Monday",
            lastMessageTime: nil,
            todaysWorkout: todaysWorkout,
            lastWorkoutTime: nil,
            currentBlock: programExists ? "Aerobic Capacity" : "No program",
            weekNumber: programExists ? 3 : 0,
            recentMetrics: nil,
            programExists: programExists,
            hasHealthData: false,
            messagesSentToday: 0,
            daysSinceLastMessage: nil
        )
    }
    
    private func setMockAPIKey() {
        UserDefaults.standard.set("mock-api-key", forKey: "OPENROUTER_API_KEY")
    }
}

// MARK: - Mock Tool Processor

class MockToolProcessor: ToolProcessor {
    var processResponseCalled = false
    var processedToolCalls: [ToolCall] = []
    var mockToolCalls: [ToolCall] = []
    var mockProcessedResponse = ProcessedResponse(
        cleanedResponse: "",
        requiresFollowUp: false,
        toolResults: []
    )
    
    override func detectToolCalls(in response: String) -> [ToolCall] {
        processResponseCalled = true
        return mockToolCalls
    }
    
    override func processResponseWithToolCalls(_ response: String) async throws -> ProcessedResponse {
        processResponseCalled = true
        processedToolCalls = detectToolCalls(in: response)
        return mockProcessedResponse
    }
}

// MARK: - Tool Call Result Extension

extension ToolProcessor.ToolCallResult: Equatable {
    public static func == (lhs: ToolProcessor.ToolCallResult, rhs: ToolProcessor.ToolCallResult) -> Bool {
        return lhs.toolName == rhs.toolName && 
               lhs.result == rhs.result && 
               lhs.success == rhs.success
    }
}