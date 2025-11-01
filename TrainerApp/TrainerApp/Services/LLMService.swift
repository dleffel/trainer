import Foundation

// MARK: - Error Types

enum LLMError: LocalizedError {
    case missingContent
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingContent: return "No content returned by the model."
        case .invalidResponse: return "Unexpected response from the model."
        case .httpError(let code): return "Network error: HTTP \(code)."
        }
    }
}

// MARK: - Protocol for Dependency Injection

protocol LLMServiceProtocol {
    func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> (content: String, reasoning: String?)
    
    func streamComplete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void
    ) async throws -> (content: String, reasoning: String?)
}

// MARK: - LLM Service Implementation

class LLMService: LLMServiceProtocol {
    // Singleton for convenience, but protocol allows dependency injection
    static let shared = LLMService()
    
    private init() {}
    
    // MARK: - Private Types
    
    /// API message structure for chat completions
    private struct APIMessage: Codable {
        let role: String
        let content: Content
        
        enum Content: Codable {
            case text(String)
            case multipart([ContentPart])
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .multipart(let parts):
                    try container.encode(parts)
                }
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .text(string)
                } else if let parts = try? container.decode([ContentPart].self) {
                    self = .multipart(parts)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Content must be string or array"
                        )
                    )
                }
            }
        }
        
        struct ContentPart: Codable {
            let type: String
            let text: String?
            let image_url: ImageURL?
            
            struct ImageURL: Codable {
                let url: String  // base64 data URL
            }
        }
    }
    
    // MARK: - Private Properties
    
    /// Reusable DateFormatter for message timestamps to avoid allocation overhead
    private static let messageTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a zzz"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    // MARK: - Public Interface
    
    func complete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) async throws -> (content: String, reasoning: String?) {
        struct RequestBody: Codable {
            let model: String
            let messages: [APIMessage]
            let include_reasoning: Bool?
        }
        struct ResponseBody: Codable {
            struct Choice: Codable {
                struct Msg: Codable {
                    let role: String
                    let content: String
                    let reasoning_content: String?
                }
                let index: Int
                let message: Msg
            }
            let choices: [Choice]
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("com.yourcompany.TrainerApp", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120.0 // 2 minutes timeout for GPT-5 responses

        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let enhancedSystemPrompt = createTemporalSystemPrompt(systemPrompt, conversationHistory: history)
            msgs.append(APIMessage(role: "system", content: .text(enhancedSystemPrompt)))
            print("🕒 TEMPORAL_DEBUG: Using enhanced system prompt in complete() method")
        }
        
        // Add messages with timestamp enhancement
        for m in history {
            msgs.append(enhanceMessageWithTimestamp(m))
        }
        
        // Debug logging for timestamp enhancement
        print("📅 TEMPORAL_DEBUG: Enhanced \(history.count) messages with timestamps")
        if let firstMessage = history.first {
            let sample = formatMessageTimestamp(firstMessage.date)
            print("📅 Sample timestamp format: \(sample)")
        }

        // Check if model supports reasoning
        let includeReasoning = supportsReasoning(model: model)
        let body = try JSONEncoder().encode(RequestBody(
            model: model,
            messages: msgs,
            include_reasoning: includeReasoning ? true : nil
        ))
        request.httpBody = body

        // Log the request if enabled
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.missingContent
        }
        let reasoning = decoded.choices.first?.message.reasoning_content
        
        if let reasoning = reasoning, !reasoning.isEmpty {
            print("🧠 Captured reasoning content (\(reasoning.count) chars)")
        }
        
        return (content: content, reasoning: reasoning)
    }
    
    /// Streaming chat completion using SSE; streams tokens via onToken and returns the full text.
    func streamComplete(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [ChatMessage],
        onToken: @escaping (String) -> Void,
        onReasoning: @escaping (String) -> Void = { _ in }
    ) async throws -> (content: String, reasoning: String?) {
        struct StreamRequestBody: Codable {
            let model: String
            let messages: [APIMessage]
            let stream: Bool
            let include_reasoning: Bool?
        }
        struct StreamDelta: Codable {
            let content: String?
            let reasoning: String?
        }
        struct StreamChoice: Codable { let delta: StreamDelta? }
        struct StreamChunk: Codable { let choices: [StreamChoice] }
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("com.yourcompany.TrainerApp", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120.0 // Keep consistent with non-streaming
        
        var msgs: [APIMessage] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let enhancedSystemPrompt = createTemporalSystemPrompt(systemPrompt, conversationHistory: history)
            msgs.append(APIMessage(role: "system", content: .text(enhancedSystemPrompt)))
            print("🕒 TEMPORAL_DEBUG: Using enhanced system prompt in streamComplete() method")
        }
        
        // Add messages with timestamp enhancement
        for m in history {
            msgs.append(enhanceMessageWithTimestamp(m))
        }
        
        // Debug logging for timestamp enhancement
        print("📅 TEMPORAL_DEBUG: Enhanced \(history.count) messages with timestamps")
        if let firstMessage = history.first {
            let sample = formatMessageTimestamp(firstMessage.date)
            print("📅 Sample timestamp format: \(sample)")
        }
        
        // Check if model supports reasoning
        let includeReasoning = supportsReasoning(model: model)
        let reqBody = StreamRequestBody(
            model: model,
            messages: msgs,
            stream: true,
            include_reasoning: includeReasoning ? true : nil
        )
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        // Stream response lines
        let (bytes, resp) = try await URLSession.shared.bytes(for: request)
        
        // If server returns an error status, consume the body to surface details, then throw
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorData = Data()
            // Accumulate any error payload (likely JSON) to help diagnose
            for try await chunk in bytes {
                errorData.append(contentsOf: [chunk])
            }
            if let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let err = (json["error"] as? [String: Any])?["message"] as? String {
                print("❌ Streaming error \(http.statusCode): \(err)")
            } else if let s = String(data: errorData, encoding: .utf8) {
                print("❌ Streaming error \(http.statusCode): \(s)")
            } else {
                print("❌ Streaming error \(http.statusCode): <no body>")
            }
            
            throw LLMError.httpError(http.statusCode)
        }
        
        var fullText = ""
        var fullReasoning = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta else { continue }
            
            // Handle reasoning tokens
            if let reasoning = delta.reasoning, !reasoning.isEmpty {
                fullReasoning += reasoning
                onReasoning(reasoning)
            }
            
            // Handle content tokens
            if let content = delta.content, !content.isEmpty {
                fullText += content
                onToken(content)
            }
        }
        
        guard !fullText.isEmpty else {
            throw LLMError.missingContent
        }
        
        if !fullReasoning.isEmpty {
            print("🧠 Captured streaming reasoning content (\(fullReasoning.count) chars)")
        }
        
        return (content: fullText, reasoning: fullReasoning.isEmpty ? nil : fullReasoning)
    }
    
    // MARK: - Model Detection
    
    /// Check if a model supports reasoning tokens
    private func supportsReasoning(model: String) -> Bool {
        let reasoningModels = [
            "openai/o1",
            "openai/o1-preview",
            "openai/o1-mini",
            "openai/o3-mini",
            "openai/gpt-5"
        ]
        
        let modelLower = model.lowercased()
        let supports = reasoningModels.contains { modelLower.contains($0.lowercased()) }
        
        if supports {
            print("🧠 Model '\(model)' supports reasoning tokens")
        }
        
        return supports
    }
    
    // MARK: - Private Helpers
    
    /// Create temporal-enhanced system prompt with current time context
    private func createTemporalSystemPrompt(
        _ systemPrompt: String, 
        conversationHistory: [ChatMessage]
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        formatter.timeZone = TimeZone.current
        
        let currentTime = DateProvider.shared.currentDate
        let currentTimeString = formatter.string(from: currentTime)
        let sessionStartTime = conversationHistory.first?.date ?? currentTime
        let sessionStartString = formatter.string(from: sessionStartTime)
        
        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let durationMinutes = Int(sessionDuration / 60)
        
        let temporalContext = """
        
        [TEMPORAL_CONTEXT]
        Current time: \(currentTimeString)
        User timezone: \(TimeZone.current.identifier)
        Conversation started: \(sessionStartString)
        Session duration: \(durationMinutes) minutes
        """
        
        let enhancedPrompt = systemPrompt + temporalContext
        
        // Debug logging
        print("🕒 TEMPORAL_DEBUG: Enhanced system prompt with temporal context")
        print("🕒 Current time: \(currentTimeString)")
        print("🕒 Session duration: \(durationMinutes) minutes")
        print("🕒 Enhanced prompt length: \(enhancedPrompt.count) characters")
        
        return enhancedPrompt
    }
    
    /// Format a message timestamp in a human-readable format with day of week
    private func formatMessageTimestamp(_ date: Date) -> String {
        return Self.messageTimestampFormatter.string(from: date)
    }
    
    /// Enhance a message with timestamp prefix for temporal context
    private func enhanceMessageWithTimestamp(_ message: ChatMessage) -> APIMessage {
        let role: String
        switch message.role {
        case .user:
            role = "user"
        case .assistant:
            role = "assistant"
        case .system:
            role = "system"
        }
        
        // If message has attachments, use multipart content
        if let attachments = message.attachments, !attachments.isEmpty {
            var parts: [APIMessage.ContentPart] = []
            
            // Add text content if present
            if !message.content.isEmpty {
                let timestamp = formatMessageTimestamp(message.date)
                let enhancedContent = message.role == .user || message.role == .assistant
                    ? "[\(timestamp)]\n\(message.content)"
                    : message.content
                
                parts.append(APIMessage.ContentPart(
                    type: "text",
                    text: enhancedContent,
                    image_url: nil
                ))
            }
            
            // Add image attachments
            for attachment in attachments where attachment.type == .image {
                let base64 = attachment.data.base64EncodedString()
                let dataUrl = "data:\(attachment.mimeType);base64,\(base64)"
                
                parts.append(APIMessage.ContentPart(
                    type: "image_url",
                    text: nil,
                    image_url: APIMessage.ContentPart.ImageURL(url: dataUrl)
                ))
            }
            
            return APIMessage(role: role, content: .multipart(parts))
        } else {
            // Text-only message
            if message.role == .user || message.role == .assistant {
                let timestamp = formatMessageTimestamp(message.date)
                let enhancedContent = "[\(timestamp)]\n\(message.content)"
                return APIMessage(role: role, content: .text(enhancedContent))
            } else {
                return APIMessage(role: role, content: .text(message.content))
            }
        }
    }
}