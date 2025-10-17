import Foundation

/// Delegate protocol for tool execution state updates
protocol ToolExecutionStateDelegate: AnyObject {
    /// Called when tool execution starts
    func toolExecutionDidStart(toolName: String, description: String)
    
    /// Called when tool execution completes
    func toolExecutionDidComplete(result: ToolProcessor.ToolCallResult)
    
    /// Called to update a message with cleaned content after tool processing
    func toolExecutionDidUpdateMessage(at index: Int, with message: ChatMessage)
}

/// Coordinates tool call detection, execution, and result formatting
/// Extracted from ConversationManager to provide focused tool processing responsibility
@MainActor
class ToolExecutionCoordinator {
    
    // MARK: - Dependencies
    
    private let toolProcessor: ToolProcessor
    private let logger = ConversationLogger.shared
    weak var delegate: ToolExecutionStateDelegate?
    
    // MARK: - Initialization
    
    init(toolProcessor: ToolProcessor = .shared) {
        self.toolProcessor = toolProcessor
    }
    
    // MARK: - Public Interface
    
    /// Result of tool execution
    struct ToolExecutionResult {
        let hasTools: Bool
        let toolResults: [ToolProcessor.ToolCallResult]
        let cleanedResponse: String
        let systemMessage: ChatMessage?
    }
    
    /// Process response for tool calls and execute them
    /// - Parameters:
    ///   - responseState: The current response state containing raw content
    ///   - messageIndex: Index of the message to update with cleaned content
    /// - Returns: Tool execution result with cleaned response and optional system message
    func processToolCalls(
        in responseState: AssistantResponseState,
        messageIndex: Int?
    ) async throws -> ToolExecutionResult {
        let processed = try await toolProcessor.processResponseWithToolCalls(responseState.content)
        
        // If tools were detected and executed
        if !processed.toolResults.isEmpty {
            logger.logTiming("tools_start", timestamp: Date().timeIntervalSince1970)
            
            // Notify delegate for UI updates (no artificial delay - tools complete quickly)
            for result in processed.toolResults {
                delegate?.toolExecutionDidStart(
                    toolName: result.toolName,
                    description: "Processing \(result.toolName)..."
                )
                delegate?.toolExecutionDidComplete(result: result)
            }
            
            // Update message with cleaned content if we have a valid index
            if let idx = messageIndex {
                let updatedMessage = createUpdatedMessage(
                    at: idx,
                    cleanedContent: processed.cleanedResponse,
                    reasoning: responseState.reasoning
                )
                delegate?.toolExecutionDidUpdateMessage(at: idx, with: updatedMessage)
            }
            
            // Format tool results as system message
            let systemMessage = MessageFactory.system(
                content: toolProcessor.formatToolResults(processed.toolResults)
            )
            
            logger.logTiming("tools_complete", timestamp: Date().timeIntervalSince1970)
            
            return ToolExecutionResult(
                hasTools: true,
                toolResults: processed.toolResults,
                cleanedResponse: processed.cleanedResponse,
                systemMessage: systemMessage
            )
        }
        
        // No tools detected - still return cleaned response for content normalization
        if let idx = messageIndex {
            let updatedMessage = createUpdatedMessage(
                at: idx,
                cleanedContent: processed.cleanedResponse,
                reasoning: responseState.reasoning
            )
            delegate?.toolExecutionDidUpdateMessage(at: idx, with: updatedMessage)
        }
        
        return ToolExecutionResult(
            hasTools: false,
            toolResults: [],
            cleanedResponse: processed.cleanedResponse,
            systemMessage: nil
        )
    }
    
    // MARK: - Private Helpers
    
    /// Create an updated message with cleaned content and completed state
    private func createUpdatedMessage(
        at index: Int,
        cleanedContent: String,
        reasoning: String?
    ) -> ChatMessage {
        // Create a base message - delegate will provide the actual message to update
        // This is just a template that delegate will use to update the real message
        return MessageFactory.assistant(
            content: cleanedContent.isEmpty ? "" : cleanedContent,
            reasoning: reasoning,
            state: .completed
        )
    }
}