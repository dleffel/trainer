import Foundation

extension URLSession {
    /// Result type for streaming logging data task
    struct StreamingLoggingResult {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        let requestId: UUID
    }
    
    /// Streaming data task with complete API logging integration
    /// This method starts logging the request and returns a request ID to track the streaming response
    func streamingLoggingDataTask(
        with request: URLRequest
    ) async throws -> StreamingLoggingResult {
        print("🔍 DEBUG streamingLoggingDataTask: CALLED with URL: \(request.url?.absoluteString ?? "nil")")
        
        // Check if logging is enabled
        let loggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
        print("🔍 DEBUG streamingLoggingDataTask: API logging enabled = \(loggingEnabled)")
        
        // Start logging the request immediately
        let requestId = EnhancedAPILogger.shared.logStreamingRequestStart(request)
        print("🔍 DEBUG streamingLoggingDataTask: Got request ID = \(requestId)")
        
        do {
            // Start the streaming request
            let (bytes, response) = try await self.bytes(for: request)
            print("🔍 DEBUG streamingLoggingDataTask: Got streaming response")
            
            // Log that streaming has started
            EnhancedAPILogger.shared.logStreamingStart(requestId)
            print("🔍 DEBUG streamingLoggingDataTask: Logged streaming start")
            
            return StreamingLoggingResult(
                bytes: bytes,
                response: response,
                requestId: requestId
            )
        } catch {
            // Log the error if request fails immediately
            EnhancedAPILogger.shared.logStreamingComplete(
                requestId,
                response: nil,
                fullResponseText: "",
                error: error
            )
            throw error
        }
    }
    
    /// Complete streaming logging after response assembly
    /// Call this after you've finished processing all streaming chunks
    func completeStreamingLog(
        requestId: UUID,
        response: URLResponse?,
        fullResponseText: String,
        error: Error? = nil
    ) {
        EnhancedAPILogger.shared.logStreamingComplete(
            requestId,
            response: response,
            fullResponseText: fullResponseText,
            error: error
        )
    }
}

// MARK: - Compatibility Extensions

extension URLSession {
    /// Convenience method for backwards compatibility with existing logging
    /// This bridges the gap between the new streaming logging and existing patterns
    func enhancedStreamingDataTask(with request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await streamingLoggingDataTask(with: request)
        
        // Accumulate all data for non-streaming use case
        var accumulatedData = Data()
        for try await byte in result.bytes {
            accumulatedData.append(byte)
        }
        
        // Complete the logging with the full response data
        let responseText = String(data: accumulatedData, encoding: .utf8) ?? ""
        completeStreamingLog(
            requestId: result.requestId,
            response: result.response,
            fullResponseText: responseText
        )
        
        return (accumulatedData, result.response)
    }
}