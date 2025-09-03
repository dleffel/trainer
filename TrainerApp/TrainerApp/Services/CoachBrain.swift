import Foundation

/// Protocol for testability and dependency injection
protocol CoachBrainProtocol {
    func evaluateContext(_ context: CoachContext) async throws -> CoachDecision
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult])
}

/// Pure decision-making engine for the coach
/// This is a stateless service focused only on LLM logic and tool processing
class CoachBrain: CoachBrainProtocol {
    
    // MARK: - Dependencies
    private let toolProcessor: ToolProcessor
    private let systemPromptLoader: SystemPromptLoader.Type
    
    // MARK: - Initialization
    init(
        toolProcessor: ToolProcessor = .shared,
        systemPromptLoader: SystemPromptLoader.Type = SystemPromptLoader.self
    ) {
        self.toolProcessor = toolProcessor
        self.systemPromptLoader = systemPromptLoader
    }
    
    // MARK: - Public Interface
    
    /// Evaluate context and decide whether to send a message
    func evaluateContext(_ context: CoachContext) async throws -> CoachDecision {
        print("🤔 CoachBrain: Starting evaluation...")
        
        // Get the API key
        guard let apiKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"),
              !apiKey.isEmpty else {
            print("❌ CoachBrain: No API key configured")
            return CoachDecision(
                shouldSendMessage: true,
                message: "Ready to start your rowing journey? Open the app to add your API key and begin!",
                reasoning: "No API key configured - guiding user to complete setup"
            )
        }
        
        // Build prompts
        let systemPrompt = buildEnhancedSystemPrompt()
        let contextPrompt = context.contextPrompt
        
        // Initial LLM call
        let initialPrompt = """
        \(contextPrompt)
        
        IMPORTANT: You must check the actual training status before making any claims.
        
        If the context shows "No active training program":
        1. First use [TOOL_CALL: get_training_status] to verify
        2. If confirmed no program, use [TOOL_CALL: start_training_program]
        3. Then use [TOOL_CALL: plan_week] to create the schedule
        4. Only after these succeed, craft your message
        
        Start by checking the current state with tools, then decide on your message.
        """
        
        do {
            print("📤 CoachBrain: Making initial LLM call...")
            var response = try await LLMClient.complete(
                apiKey: apiKey,
                model: "gpt-5",
                systemPrompt: systemPrompt,
                history: [ChatMessage(role: .user, content: initialPrompt)]
            )
            
            print("📥 CoachBrain: Initial response received")
            
            // Process any tool calls
            let (finalResponse, toolResults) = await processToolCalls(in: response)
            
            // If tools were executed, make a follow-up call with results
            if !toolResults.isEmpty {
                print("🔧 CoachBrain: Tools executed, making follow-up call...")
                
                let followUpPrompt = buildFollowUpPrompt(toolResults: toolResults)
                
                response = try await LLMClient.complete(
                    apiKey: apiKey,
                    model: "gpt-5",
                    systemPrompt: systemPrompt,
                    history: [
                        ChatMessage(role: .assistant, content: finalResponse),
                        ChatMessage(role: .user, content: followUpPrompt)
                    ]
                )
                
                print("📥 CoachBrain: Final response received")
            }
            
            return parseCoachDecision(response)
            
        } catch {
            print("❌ CoachBrain: LLM call failed: \(error)")
            return CoachDecision(
                shouldSendMessage: false,
                message: nil,
                reasoning: "LLM call failed: \(error)"
            )
        }
    }
    
    /// Process tool calls in a response
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult]) {
        do {
            let processed = try await toolProcessor.processResponseWithToolCalls(response)
            
            if processed.requiresFollowUp {
                print("🔧 CoachBrain: Executed \(processed.toolResults.count) tools")
                for result in processed.toolResults {
                    print("   ↳ \(result.toolName): \(result.success ? "✅" : "❌")")
                }
            }
            
            return (processed.cleanedResponse, processed.toolResults)
        } catch {
            print("❌ CoachBrain: Tool processing failed: \(error)")
            return (response, [])
        }
    }
    
    // MARK: - Private Methods
    
    private func buildEnhancedSystemPrompt() -> String {
        // Load the full rowing coach system prompt
        let systemPrompt = systemPromptLoader.loadSystemPrompt()
        
        return """
        \(systemPrompt)
        
        ## PROACTIVE MESSAGING MODE
        
        You are evaluating whether to send a proactive message to your athlete.
        This is a background check - the athlete hasn't opened the app.
        
        ### CRITICAL RULE: ALWAYS USE TOOLS BEFORE MAKING CLAIMS
        
        NEVER claim to have done something without actually using the tools to do it.
        If you say "I've initialized your program", you MUST have called [TOOL_CALL: start_training_program] first.
        
        ### PROACTIVE DECISION FLOW:
        
        1. FIRST, check the current state:
           - Use [TOOL_CALL: get_training_status] to check if a program exists
        
        2. IF no program exists (status shows "No program started"):
            - Use [TOOL_CALL: start_training_program] to initialize
            - Then use [TOOL_CALL: plan_week] to create the first week
            - Then use [TOOL_CALL: generate_workout_instructions(date: "today")] for today's details
            - ONLY AFTER these succeed, send a brief message with the link
        
        3. IF program exists AND it's time for a workout reminder:
            - Use [TOOL_CALL: get_weekly_schedule] to check today's plan
            - Use [TOOL_CALL: generate_workout_instructions(date: "today")] to create instructions
            - Send a brief message with ONLY the link, NOT the full workout details
        
        ### AVAILABLE TOOLS:
        - [TOOL_CALL: get_training_status] - Check if program exists
        - [TOOL_CALL: get_health_data] - Check health data availability
        - [TOOL_CALL: start_training_program] - Initialize training program
        - [TOOL_CALL: plan_week] - Plan the current/next week
        - [TOOL_CALL: get_weekly_schedule] - View current week's plan
        - [TOOL_CALL: generate_workout_instructions(date: "today")] - Generate detailed workout instructions
        
        ### RESPONSE FORMAT:
        
        If you need to use tools, your response should look like:
        Let me check your training status first.
        [TOOL_CALL: get_training_status]
        
        If no program exists:
        I'll set up your training program now.
        [TOOL_CALL: start_training_program]
        [TOOL_CALL: plan_week]
        [TOOL_CALL: generate_workout_instructions(date: "today")]
        
        After tools are executed, provide:
        SEND: [Yes/No]
        REASONING: [One sentence explaining why]
        MESSAGE: [If Yes, the exact message based on what actually happened]
        
        ### CRITICAL: WORKOUT DETAILS IN PROACTIVE MESSAGES
        
        NEVER include full workout details (HR zones, sets/reps, warm-up, etc.) in proactive messages.
        Instead:
        1. Use [TOOL_CALL: generate_workout_instructions(date: "today")] to create detailed instructions
        2. The tool will save instructions and return a link
        3. Include ONLY the link in your message, like: "I've prepared your workout details. 📋 View instructions: trainer://calendar/2024-01-15"
        
        Example BAD message (too long):
        "Today's workout: Spin Bike 60 min easy UT2
        - Warm-up: 10 min progressive...
        - Main: 40 min at 106-123 BPM...
        [etc...]"
        
        Example GOOD message (brief with link):
        "I've initialized your 20-week program starting with Aerobic Capacity. Today is a 60-minute easy spin bike session. 📋 View detailed instructions: trainer://calendar/2024-08-31"
        """
    }
    
    private func buildFollowUpPrompt(toolResults: [ToolProcessor.ToolCallResult]) -> String {
        let toolResultsFormatted = formatToolResults(toolResults)
        return """
        Based on the tool results:
        \(toolResultsFormatted)
        
        Now provide your final decision:
        SEND: [Yes/No]
        REASONING: [One sentence explaining why]
        MESSAGE: [If Yes, the exact message to send to the athlete]
        """
    }
    
    private func formatToolResults(_ results: [ToolProcessor.ToolCallResult]) -> String {
        return results.map { result in
            if result.success {
                return "[\(result.toolName) result]:\n\(result.result)"
            } else {
                return "[\(result.toolName) failed]: \(result.error ?? "Unknown error")"
            }
        }.joined(separator: "\n\n")
    }
    
    private func parseCoachDecision(_ response: String) -> CoachDecision {
        let lines = response.split(separator: "\n", omittingEmptySubsequences: false)
        var shouldSend = false
        var reasoning = ""
        var message: String?
        var isCapturingMessage = false
        var messageLines: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if we're in message capture mode
            if isCapturingMessage {
                // Stop capturing if we hit another field marker
                if trimmed.hasPrefix("SEND:") || trimmed.hasPrefix("REASONING:") {
                    isCapturingMessage = false
                } else {
                    // Add this line to the message
                    messageLines.append(String(line))
                }
            }
            
            if trimmed.hasPrefix("SEND:") {
                let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                shouldSend = value.lowercased() == "yes"
                isCapturingMessage = false
            } else if trimmed.hasPrefix("REASONING:") {
                reasoning = String(trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces))
                isCapturingMessage = false
            } else if trimmed.hasPrefix("MESSAGE:") {
                // Get what's after MESSAGE: on the same line
                let sameLineContent = String(trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces))
                if !sameLineContent.isEmpty {
                    messageLines.append(sameLineContent)
                }
                // Start capturing subsequent lines
                isCapturingMessage = true
            }
        }
        
        // Join message lines if we captured any
        if !messageLines.isEmpty {
            message = messageLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Don't send empty messages
            if message?.isEmpty == true {
                message = nil
            }
        }
        
        // Debug logging
        print("🔍 ParseCoachDecision Debug:")
        print("   Response length: \(response.count)")
        print("   Should send: \(shouldSend)")
        print("   Reasoning: \(reasoning)")
        print("   Message: \(message ?? "nil")")
        print("   Message lines captured: \(messageLines.count)")
        
        return CoachDecision(
            shouldSendMessage: shouldSend,
            message: message,
            reasoning: reasoning
        )
    }
}

// MARK: - Mock Implementation for Testing

/// Mock implementation for unit testing
class MockCoachBrain: CoachBrainProtocol {
    var shouldSendMessage = false
    var mockMessage = "Test message"
    var mockReasoning = "Test reasoning"
    var processToolCallsWasCalled = false
    
    func evaluateContext(_ context: CoachContext) async throws -> CoachDecision {
        return CoachDecision(
            shouldSendMessage: shouldSendMessage,
            message: shouldSendMessage ? mockMessage : nil,
            reasoning: mockReasoning
        )
    }
    
    func processToolCalls(in response: String) async throws -> (processedResponse: String, toolResults: [ToolProcessor.ToolCallResult]) {
        processToolCallsWasCalled = true
        return (response, [])
    }
}