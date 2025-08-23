import Foundation

/// Represents a single API request/response log entry
struct APILogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let requestURL: String
    let requestMethod: String
    let requestHeaders: [String: String]
    let requestBody: Data?
    let responseStatusCode: Int?
    let responseHeaders: [String: String]?
    let responseBody: Data?
    let duration: TimeInterval
    let error: String?
    let apiKeyPreview: String // Last 4 chars only for security
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        requestURL: String,
        requestMethod: String,
        requestHeaders: [String: String],
        requestBody: Data?,
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: Data? = nil,
        duration: TimeInterval = 0,
        error: String? = nil,
        apiKeyPreview: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.requestURL = requestURL
        self.requestMethod = requestMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
        self.error = error
        self.apiKeyPreview = apiKeyPreview
    }
    
    /// Computed property to get pretty-printed request body as string
    var requestBodyString: String? {
        guard let data = requestBody else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: prettyData, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Computed property to get pretty-printed response body as string
    var responseBodyString: String? {
        guard let data = responseBody else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: prettyData, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Indicates if the request was successful (2xx status code)
    var isSuccess: Bool {
        guard let statusCode = responseStatusCode else { return false }
        return (200...299).contains(statusCode)
    }
    
    /// Generate cURL command for this request
    var curlCommand: String {
        var components = ["curl"]
        
        // Add method
        components.append("-X \(requestMethod)")
        
        // Add headers
        for (key, value) in requestHeaders {
            // Mask authorization header
            if key.lowercased() == "authorization" {
                let maskedValue = maskAuthorizationValue(value)
                components.append("-H '\(key): \(maskedValue)'")
            } else {
                components.append("-H '\(key): \(value)'")
            }
        }
        
        // Add body if present
        if let bodyString = requestBodyString {
            let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\"'\"'")
            components.append("-d '\(escapedBody)'")
        }
        
        // Add URL
        components.append("'\(requestURL)'")
        
        return components.joined(separator: " \\\n  ")
    }
    
    private func maskAuthorizationValue(_ value: String) -> String {
        if value.hasPrefix("Bearer ") {
            let token = String(value.dropFirst(7))
            if token.count > 4 {
                let lastFour = String(token.suffix(4))
                return "Bearer ***\(lastFour)"
            }
        }
        return "***"
    }
}

// MARK: - Date Formatting
extension APILogEntry {
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var formattedDuration: String {
        return String(format: "%.3fs", duration)
    }
}