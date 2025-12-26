import Foundation

/// Service for communicating with the Organizer Exercise API
/// Handles all HTTP operations with Basic Auth authentication
class ExerciseAPIService {
    static let shared = ExerciseAPIService()
    
    private let baseURL = "https://api.organizer.dannyleffel.com/api/exercise"
    private let credentials = ExerciseAPICredentials.shared
    
    private init() {}
    
    // MARK: - Date Formatting
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
    
    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
    
    // MARK: - Exercise Entry Operations
    
    /// Delete an exercise entry and all its nested items
    func deleteEntry(for date: Date) async throws {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }
    
    /// Create or update an exercise entry for a date
    func createEntry(
        for date: Date,
        primaryModality: String?,
        notes: String?
    ) async throws -> ExerciseEntryResponse {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)")!
        let body = ExerciseEntryRequest(primaryModality: primaryModality, dayNotes: notes)
        return try await performRequest(url: url, method: "PUT", body: body)
    }
    
    /// Get an entry with all nested items for a specific date
    func getEntry(for date: Date) async throws -> ExerciseEntryWithItems? {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)")!
        return try await performRequest(url: url, method: "GET")
    }
    
    // MARK: - Strength Exercise Operations
    
    /// Add a strength exercise to a date
    func addStrengthExercise(
        date: Date,
        exercise: StrengthExerciseRequest
    ) async throws -> StrengthExerciseResponse {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)/strength")!
        return try await performRequest(url: url, method: "POST", body: exercise)
    }
    
    /// Add a set to a strength exercise
    func addStrengthSet(
        exerciseId: String,
        set: StrengthSetRequest
    ) async throws -> StrengthSetResponse {
        let url = URL(string: "\(baseURL)/strength/\(exerciseId)/sets")!
        return try await performRequest(url: url, method: "POST", body: set)
    }
    
    // MARK: - Cardio Workout Operations
    
    /// Add a cardio workout to a date
    func addCardioWorkout(
        date: Date,
        workout: CardioWorkoutRequest
    ) async throws -> CardioWorkoutResponse {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)/cardio")!
        return try await performRequest(url: url, method: "POST", body: workout)
    }
    
    /// Add an interval to a cardio workout
    func addCardioInterval(
        workoutId: String,
        interval: CardioIntervalRequest
    ) async throws -> CardioIntervalResponse {
        let url = URL(string: "\(baseURL)/cardio/\(workoutId)/intervals")!
        return try await performRequest(url: url, method: "POST", body: interval)
    }
    
    // MARK: - Yoga/Mobility Operations
    
    /// Create or update yoga/mobility workout for a date
    func setYogaMobility(
        date: Date,
        workout: YogaMobilityRequest
    ) async throws -> YogaMobilityResponse {
        let dateString = formatDate(date)
        let url = URL(string: "\(baseURL)/entries/\(dateString)/yoga")!
        return try await performRequest(url: url, method: "PUT", body: workout)
    }
    
    /// Add a movement to a yoga/mobility workout
    func addYogaMovement(
        workoutId: String,
        movement: YogaMovementRequest
    ) async throws -> YogaMovementResponse {
        let url = URL(string: "\(baseURL)/yoga/\(workoutId)/movements")!
        return try await performRequest(url: url, method: "POST", body: movement)
    }
    
    // MARK: - Private Helpers
    
    /// Perform an HTTP request with optional body
    private func performRequest<T: Decodable, B: Encodable>(
        url: URL,
        method: String,
        body: B? = nil as EmptyBody?
    ) async throws -> T {
        guard credentials.hasCredentials else {
            print("❌ Exercise API Error: Missing credentials")
            throw ExerciseAPIError.missingCredentials
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        // Always log the request details
        print("📤 Exercise API Request: \(method) \(url.absoluteString)")
        
        if let body = body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            
            if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                print("   Request Body: \(jsonString)")
            }
        } else {
            print("   Request Body: (none)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Exercise API Error: Invalid response (not HTTP)")
            throw ExerciseAPIError.invalidResponse
        }
        
        // Always log response status and body
        let responseString = String(data: data, encoding: .utf8) ?? "(binary data)"
        print("📥 Exercise API Response: \(httpResponse.statusCode)")
        print("   Response Body: \(responseString.prefix(1000))")
        
        switch httpResponse.statusCode {
        case 200...299:
            print("✅ Exercise API Success")
            
            // Handle empty response for DELETE
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            
            // Handle null response (entry not found)
            if data.isEmpty || responseString == "null" {
                if T.self == Optional<ExerciseEntryWithItems>.self {
                    return Optional<ExerciseEntryWithItems>.none as! T
                }
            }
            
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("❌ Exercise API Decode Error: \(error)")
                throw error
            }
            
        case 401:
            print("❌ Exercise API Error: Not authenticated (401)")
            throw ExerciseAPIError.notAuthenticated
            
        case 404:
            print("❌ Exercise API Error: Not found (404)")
            // For GET requests, 404 might mean "not found" which is OK
            if method == "GET" {
                if T.self == Optional<ExerciseEntryWithItems>.self {
                    return Optional<ExerciseEntryWithItems>.none as! T
                }
            }
            throw ExerciseAPIError.notFound
            
        case 405:
            print("❌ Exercise API Error: Method Not Allowed (405)")
            print("   The HTTP method '\(method)' is not allowed for URL: \(url.absoluteString)")
            print("   Check that the endpoint and method match the API specification")
            throw ExerciseAPIError.httpError(405)
            
        default:
            // Try to extract error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                print("❌ Exercise API Error (\(httpResponse.statusCode)): \(errorMessage)")
            } else {
                print("❌ Exercise API Error: HTTP \(httpResponse.statusCode)")
            }
            throw ExerciseAPIError.httpError(httpResponse.statusCode)
        }
    }
    
    /// Perform a request without a body
    private func performRequest<T: Decodable>(
        url: URL,
        method: String
    ) async throws -> T {
        try await performRequest(url: url, method: method, body: nil as EmptyBody?)
    }
}

// MARK: - Helper Types

/// Empty body for requests without payload
private struct EmptyBody: Encodable {}

/// Empty response for DELETE operations
struct EmptyResponse: Decodable {}
