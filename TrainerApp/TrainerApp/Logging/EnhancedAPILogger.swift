import Foundation
import Combine

/// Enhanced API Logger with streaming support and better debugging
final class EnhancedAPILogger {
    static let shared = EnhancedAPILogger()
    
    private let persistence = LoggingPersistence()
    private let queue = DispatchQueue(label: "com.trainerapp.enhancedapilogger", qos: .background)
    private var activeRequests = [UUID: ActiveRequest]()
    private let activeRequestsLock = NSLock()
    
    /// Timeout duration in seconds
    private let timeoutDuration: TimeInterval = 30.0
    
    /// Timer to check for timeouts
    private var timeoutTimer: Timer?
    
    private var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    }
    
    /// Structure to track active requests
    private struct ActiveRequest {
        let id: UUID
        let request: URLRequest
        let startTime: Date
        var hasReceivedData: Bool = false
        var streamingStartTime: Date?
        var bytesReceived: Int64 = 0
    }
    
    private init() {
        startTimeoutMonitor()
    }
    
    deinit {
        timeoutTimer?.invalidate()
    }
    
    // MARK: - Request Lifecycle
    
    /// Log the start of a request
    func logRequestStart(_ request: URLRequest) -> UUID {
        guard isLoggingEnabled else { return UUID() }
        
        let requestId = UUID()
        let activeRequest = ActiveRequest(
            id: requestId,
            request: request,
            startTime: Date()
        )
        
        activeRequestsLock.lock()
        activeRequests[requestId] = activeRequest
        activeRequestsLock.unlock()
        
        // Log initial request entry
        let entry = createRequestEntry(
            id: requestId,
            request: request,
            phase: .sent,
            startTime: activeRequest.startTime
        )
        
        queue.async { [weak self] in
            self?.persistence.append(entry)
        }
        
        return requestId
    }
    
    /// Log streaming has started
    func logStreamingStart(_ requestId: UUID) {
        guard isLoggingEnabled else { return }
        
        activeRequestsLock.lock()
        if var activeRequest = activeRequests[requestId] {
            activeRequest.streamingStartTime = Date()
            activeRequest.hasReceivedData = true
            activeRequests[requestId] = activeRequest
            
            // Log streaming status
            let entry = createStreamingStatusEntry(
                id: requestId,
                status: .streamingStarted,
                timestamp: Date()
            )
            
            queue.async { [weak self] in
                self?.persistence.append(entry)
            }
        }
        activeRequestsLock.unlock()
    }
    
    /// Log streaming progress
    func logStreamingProgress(_ requestId: UUID, bytesReceived: Int64) {
        guard isLoggingEnabled else { return }
        
        activeRequestsLock.lock()
        if var activeRequest = activeRequests[requestId] {
            activeRequest.bytesReceived = bytesReceived
            activeRequests[requestId] = activeRequest
        }
        activeRequestsLock.unlock()
    }
    
    /// Log response completion
    func logResponseComplete(
        _ requestId: UUID,
        response: URLResponse?,
        data: Data?,
        error: Error?
    ) {
        guard isLoggingEnabled else { return }
        
        activeRequestsLock.lock()
        guard let activeRequest = activeRequests[requestId] else {
            activeRequestsLock.unlock()
            return
        }
        activeRequests.removeValue(forKey: requestId)
        activeRequestsLock.unlock()
        
        let duration = Date().timeIntervalSince(activeRequest.startTime)
        
        // Create response entry
        let entry = createResponseEntry(
            id: requestId,
            request: activeRequest.request,
            response: response,
            data: data,
            error: error,
            duration: duration,
            phase: error != nil ? .failed : .completed,
            bytesReceived: activeRequest.bytesReceived
        )
        
        queue.async { [weak self] in
            self?.persistence.append(entry)
        }
    }
    
    // MARK: - Timeout Monitoring
    
    private func startTimeoutMonitor() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkForTimeouts()
        }
    }
    
    private func checkForTimeouts() {
        guard isLoggingEnabled else { return }
        
        let now = Date()
        var timedOutRequests: [ActiveRequest] = []
        
        activeRequestsLock.lock()
        for (id, request) in activeRequests {
            let elapsed = now.timeIntervalSince(request.startTime)
            if elapsed > timeoutDuration {
                timedOutRequests.append(request)
                activeRequests.removeValue(forKey: id)
            }
        }
        activeRequestsLock.unlock()
        
        // Log timeouts
        for request in timedOutRequests {
            let entry = createTimeoutEntry(
                id: request.id,
                request: request.request,
                duration: timeoutDuration
            )
            
            queue.async { [weak self] in
                self?.persistence.append(entry)
            }
        }
    }
    
    // MARK: - Entry Creation
    
    private func createRequestEntry(
        id: UUID,
        request: URLRequest,
        phase: APILogPhase,
        startTime: Date
    ) -> APILogEntry {
        let requestURL = request.url?.absoluteString ?? "Unknown"
        let requestMethod = request.httpMethod ?? "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody
        let apiKeyPreview = extractAPIKeyPreview(from: requestHeaders)
        
        return APILogEntry(
            id: id,
            timestamp: startTime,
            requestURL: requestURL,
            requestMethod: requestMethod,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            phase: phase,
            apiKeyPreview: apiKeyPreview
        )
    }
    
    private func createResponseEntry(
        id: UUID,
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        error: Error?,
        duration: TimeInterval,
        phase: APILogPhase,
        bytesReceived: Int64
    ) -> APILogEntry {
        let requestURL = request.url?.absoluteString ?? "Unknown"
        let requestMethod = request.httpMethod ?? "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody
        let apiKeyPreview = extractAPIKeyPreview(from: requestHeaders)
        
        var responseStatusCode: Int?
        var responseHeaders: [String: String]?
        
        if let httpResponse = response as? HTTPURLResponse {
            responseStatusCode = httpResponse.statusCode
            responseHeaders = httpResponse.allHeaderFields as? [String: String]
        }
        
        return APILogEntry(
            id: id,
            timestamp: Date(),
            requestURL: requestURL,
            requestMethod: requestMethod,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: responseStatusCode,
            responseHeaders: responseHeaders,
            responseBody: data,
            duration: duration,
            error: error?.localizedDescription,
            phase: phase,
            bytesReceived: bytesReceived,
            apiKeyPreview: apiKeyPreview
        )
    }
    
    private func createStreamingStatusEntry(
        id: UUID,
        status: StreamingStatus,
        timestamp: Date
    ) -> APILogEntry {
        return APILogEntry(
            id: id,
            timestamp: timestamp,
            requestURL: "",
            requestMethod: "",
            requestHeaders: [:],
            requestBody: nil,
            phase: .streaming,
            streamingStatus: status
        )
    }
    
    private func createTimeoutEntry(
        id: UUID,
        request: URLRequest,
        duration: TimeInterval
    ) -> APILogEntry {
        let requestURL = request.url?.absoluteString ?? "Unknown"
        let requestMethod = request.httpMethod ?? "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody
        let apiKeyPreview = extractAPIKeyPreview(from: requestHeaders)
        
        return APILogEntry(
            id: id,
            timestamp: Date(),
            requestURL: requestURL,
            requestMethod: requestMethod,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            duration: duration,
            error: "Request timed out after \(Int(duration)) seconds",
            phase: .timedOut,
            apiKeyPreview: apiKeyPreview
        )
    }
    
    private func extractAPIKeyPreview(from headers: [String: String]) -> String {
        guard let authHeader = headers["Authorization"] else { return "" }
        
        if authHeader.hasPrefix("Bearer ") {
            let token = String(authHeader.dropFirst(7))
            if token.count >= 4 {
                return String(token.suffix(4))
            }
        }
        
        return ""
    }
    
    // MARK: - Query Methods
    
    /// Get all logs for a specific request ID
    func getLogs(for requestId: UUID) -> [APILogEntry] {
        return persistence.loadAll().filter { $0.id == requestId }
    }
    
    /// Get currently active requests
    func getActiveRequests() -> [APILogEntry] {
        activeRequestsLock.lock()
        let requests = activeRequests.values.map { activeRequest in
            createRequestEntry(
                id: activeRequest.id,
                request: activeRequest.request,
                phase: activeRequest.hasReceivedData ? .streaming : .sent,
                startTime: activeRequest.startTime
            )
        }
        activeRequestsLock.unlock()
        return requests
    }
}

// MARK: - Enhanced API Log Entry

extension APILogEntry {
    enum APILogPhase: String, Codable {
        case sent = "Sent"
        case streaming = "Streaming"
        case completed = "Completed"
        case failed = "Failed"
        case timedOut = "Timed Out"
    }
    
    enum StreamingStatus: String, Codable {
        case streamingStarted = "Streaming Started"
        case streamingProgress = "Streaming Progress"
        case streamingCompleted = "Streaming Completed"
    }
    
    var phase: APILogPhase?
    var streamingStatus: StreamingStatus?
    var bytesReceived: Int64?
    
    /// Check if this is an active/pending request
    var isActive: Bool {
        guard let phase = phase else { return false }
        return phase == .sent || phase == .streaming
    }
    
    /// Format bytes received for display
    var formattedBytesReceived: String? {
        guard let bytes = bytesReceived else { return nil }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Status description for UI
    var statusDescription: String {
        if let phase = phase {
            switch phase {
            case .sent:
                return "⏳ Waiting for response..."
            case .streaming:
                if let bytes = formattedBytesReceived {
                    return "📥 Streaming... (\(bytes) received)"
                }
                return "📥 Streaming response..."
            case .completed:
                return "✅ Completed"
            case .failed:
                return "❌ Failed"
            case .timedOut:
                return "⏱️ Timed out"
            }
        }
        return "Unknown"
    }
}

// MARK: - Enhanced URLSession Extension

extension URLSession {
    /// Enhanced data task with detailed logging
    func enhancedLoggingDataTask(with request: URLRequest) async throws -> (Data, URLResponse) {
        let logger = EnhancedAPILogger.shared
        let requestId = logger.logRequestStart(request)
        
        do {
            // Create custom delegate to track streaming
            let delegate = StreamingDelegate(requestId: requestId)
            let (data, response) = try await self.data(for: request, delegate: delegate)
            
            logger.logResponseComplete(requestId, response: response, data: data, error: nil)
            return (data, response)
        } catch {
            logger.logResponseComplete(requestId, response: nil, data: nil, error: error)
            throw error
        }
    }
}

// MARK: - Streaming Delegate

private class StreamingDelegate: NSObject, URLSessionDataDelegate {
    let requestId: UUID
    private var receivedData = Data()
    
    init(requestId: UUID) {
        self.requestId = requestId
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        EnhancedAPILogger.shared.logStreamingProgress(requestId, bytesReceived: Int64(receivedData.count))
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        EnhancedAPILogger.shared.logStreamingStart(requestId)
        return .allow
    }
}