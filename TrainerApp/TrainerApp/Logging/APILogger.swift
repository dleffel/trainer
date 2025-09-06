import Foundation

/// Singleton class responsible for logging API requests and responses
final class APILogger {
    static let shared = APILogger()
    
    private let persistence = LoggingPersistence()
    private let queue = DispatchQueue(label: "com.trainerapp.apilogger", qos: .background)
    private var isLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "APILoggingEnabled")
    }
    
    private init() {}
    
    /// Log an API request/response cycle
    func log(request: URLRequest, response: URLResponse?, data: Data?, error: Error?, startTime: Date) {
        guard isLoggingEnabled else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        queue.async { [weak self] in
            let logEntry = self?.createLogEntry(
                request: request,
                response: response,
                data: data,
                error: error,
                duration: duration
            )
            
            if let entry = logEntry {
                self?.persistence.append(entry)
            }
        }
    }
    
    /// Create a log entry from request/response data
    private func createLogEntry(
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        error: Error?,
        duration: TimeInterval
    ) -> APILogEntry {
        // Extract request details
        let requestURL = request.url?.absoluteString ?? "Unknown"
        let requestMethod = request.httpMethod ?? "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBody = request.httpBody
        
        // Extract API key preview
        let apiKeyPreview = extractAPIKeyPreview(from: requestHeaders)
        
        // Extract response details
        var responseStatusCode: Int?
        var responseHeaders: [String: String]?
        
        if let httpResponse = response as? HTTPURLResponse {
            responseStatusCode = httpResponse.statusCode
            responseHeaders = httpResponse.allHeaderFields as? [String: String]
        }
        
        // Create error message if needed
        let errorMessage = error?.localizedDescription
        
        return APILogEntry(
            requestURL: requestURL,
            requestMethod: requestMethod,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: responseStatusCode,
            responseHeaders: responseHeaders,
            responseBody: data,
            duration: duration,
            error: errorMessage,
            apiKeyPreview: apiKeyPreview
        )
    }
    
    /// Extract last 4 characters of API key from headers
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
    
    /// Get all logged entries
    func getAllLogs() -> [APILogEntry] {
        return persistence.loadAll()
    }
    
    /// Get logs filtered by date range
    func getLogs(from startDate: Date, to endDate: Date) -> [APILogEntry] {
        return persistence.loadAll().filter { log in
            log.timestamp >= startDate && log.timestamp <= endDate
        }
    }
    
    /// Get logs filtered by status code
    func getLogs(withStatusCode statusCode: Int) -> [APILogEntry] {
        return persistence.loadAll().filter { log in
            log.responseStatusCode == statusCode
        }
    }
    
    /// Get logs with errors
    func getErrorLogs() -> [APILogEntry] {
        return persistence.loadAll().filter { log in
            log.error != nil || !(log.isSuccess)
        }
    }
    
    /// Clear all logs
    func clearAllLogs() {
        queue.async { [weak self] in
            self?.persistence.clearAll()
        }
    }
    
    /// Export logs as JSON
    func exportLogsAsJSON() -> Data? {
        let logs = getAllLogs()
        return try? JSONEncoder().encode(logs)
    }
    
    /// Export logs as CSV
    func exportLogsAsCSV() -> String {
        let logs = getAllLogs()
        var csv = "Timestamp,Method,URL,Status Code,Duration,Error\n"
        
        for log in logs {
            let timestamp = log.formattedTimestamp
            let method = log.requestMethod
            let url = log.requestURL
            let statusCode = log.responseStatusCode.map(String.init) ?? "N/A"
            let duration = log.formattedDuration
            let error = log.error ?? ""
            
            csv += "\"\(timestamp)\",\"\(method)\",\"\(url)\",\"\(statusCode)\",\"\(duration)\",\"\(error)\"\n"
        }
        
        return csv
    }
    
    /// Enable or disable logging
    func setLoggingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "APILoggingEnabled")
    }
    
    /// Get storage info
    func getStorageInfo() -> (logCount: Int, oldestLog: Date?, newestLog: Date?) {
        let logs = getAllLogs()
        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        
        return (
            logCount: logs.count,
            oldestLog: sorted.first?.timestamp,
            newestLog: sorted.last?.timestamp
        )
    }
}