import Foundation

extension URLSession {
    /// Create a logging-enabled URLSession
    static var loggingSession: URLSession {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration)
    }
    
    /// Data task with automatic API logging
    func loggingDataTask(with request: URLRequest) async throws -> (Data, URLResponse) {
        let startTime = Date()
        
        do {
            let (data, response) = try await self.data(for: request)
            
            // Log successful request
            APILogger.shared.log(
                request: request,
                response: response,
                data: data,
                error: nil,
                startTime: startTime
            )
            
            return (data, response)
        } catch {
            // Log failed request
            APILogger.shared.log(
                request: request,
                response: nil,
                data: nil,
                error: error,
                startTime: startTime
            )
            
            throw error
        }
    }
    
    /// Legacy completion handler version for compatibility
    func loggingDataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let startTime = Date()
        
        return self.dataTask(with: request) { data, response, error in
            // Log the request/response
            APILogger.shared.log(
                request: request,
                response: response,
                data: data,
                error: error,
                startTime: startTime
            )
            
            // Call original completion handler
            completionHandler(data, response, error)
        }
    }
}

/// Extension to make URLSession use logging by default for specific methods
extension URLSession {
    /// Convenience method to create logged data tasks using async/await
    func loggedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await loggingDataTask(with: request)
    }
}

// MARK: - Streaming Logging Support
extension URLSession {
    /// Data task with streaming support and comprehensive logging
    func streamingLoggingDataTask(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse, UUID) {
        print("🔍 DEBUG streamingLoggingDataTask: CALLED with URL: \(request.url?.absoluteString ?? "nil")")
        let loggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
        print("🔍 DEBUG streamingLoggingDataTask: API logging enabled = \(loggingEnabled)")
        
        guard loggingEnabled else {
            // If logging is disabled, fall back to regular streaming
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            return (bytes, response, UUID()) // Return dummy UUID
        }
        
        // Start logging the request
        let logId = EnhancedAPILogger.shared.logStreamingRequestStart(request)
        
        // Perform the actual streaming request
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        return (bytes, response, logId)
    }
    
    /// Complete the streaming log entry with response data
    func completeStreamingLog(id: UUID, response: URLResponse, responseBody: String, error: Error?) {
        let loggingEnabled = UserDefaults.standard.bool(forKey: "APILoggingEnabled")
        guard loggingEnabled else { return }
        
        EnhancedAPILogger.shared.logStreamingComplete(
            id,
            response: response,
            fullResponseText: responseBody,
            error: error
        )
    }
}