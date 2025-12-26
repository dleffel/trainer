import Foundation

/// Service that uses LLM to map workout data from TrainerApp format to Exercise API format
/// Uses GPT-5.2-mini via OpenRouter for efficient, intelligent data transformation
class WorkoutToAPIMapper {
    static let shared = WorkoutToAPIMapper()
    
    private let model = "openai/gpt-4o-mini"
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Map workout day and results to API format using LLM
    /// - Parameters:
    ///   - workoutDay: The workout day with structured workout plan
    ///   - results: Logged workout results for the day
    /// - Returns: Mapped data ready for API submission
    func mapWorkoutToAPI(
        workoutDay: WorkoutDay,
        results: [WorkoutSetResult]
    ) async throws -> MappedDayData {
        let prompt = buildMappingPrompt(workoutDay: workoutDay, results: results)
        
        print("🔄 WorkoutToAPIMapper: Calling LLM for data mapping...")
        let response = try await callLLM(prompt: prompt)
        
        print("📝 WorkoutToAPIMapper: Parsing LLM response...")
        return try parseMappingResponse(response)
    }
    
    // MARK: - Prompt Building
    
    private func buildMappingPrompt(workoutDay: WorkoutDay, results: [WorkoutSetResult]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        // Encode structured workout
        var workoutJSON = "null"
        if let workout = workoutDay.structuredWorkout {
            if let data = try? encoder.encode(workout),
               let json = String(data: data, encoding: .utf8) {
                workoutJSON = json
            }
        }
        
        // Encode results
        var resultsJSON = "[]"
        if !results.isEmpty {
            if let data = try? encoder.encode(results),
               let json = String(data: data, encoding: .utf8) {
                resultsJSON = json
            }
        }
        
        // Legacy planned workout text
        let legacyWorkout = workoutDay.plannedWorkout ?? "none"
        
        return """
        You are a data mapping assistant. Convert the following workout data from the TrainerApp format to the Organizer Exercise API format.

        ## Source Data

        ### Structured Workout Plan (JSON) - THE COACH'S PRESCRIPTION:
        \(workoutJSON)

        ### Legacy Planned Workout (text) - ADDITIONAL COACH NOTES:
        \(legacyWorkout)

        ### Logged Results (JSON) - WHAT THE ATHLETE ACTUALLY DID:
        \(resultsJSON)

        ## CRITICAL: Understanding Target vs Actual Fields

        The API has TWO types of fields for each metric:
        
        1. **TARGET FIELDS** (from the workout plan/prescription):
           - targetReps, targetLoad, targetRir (strength)
           - targetDuration, targetDistance, targetPace, targetCadence, targetHeartRate, targetPower (cardio)
           - These come from the STRUCTURED WORKOUT PLAN
           - These are STRINGS that can include ranges like "8-10", "Z2 (115-125bpm)", "20-22 spm"
        
        2. **ACTUAL FIELDS** (from logged results):
           - reps, load, rir (strength)
           - durationSec, distanceM, paceSecPerKm, cadence, strokeRateSpm, avgHeartRate, avgPowerW (cardio)
           - These come from the LOGGED RESULTS
           - These are NUMBERS representing what was actually achieved

        ## Target API Schema

        ```json
        {
            "entry": {
                "primaryModality": "strength|rowing|spinning|running|mobility|hiking|rest",
                "dayNotes": "string or null"
            },
            "strengthExercises": [
                {
                    "name": "string - exercise name",
                    "notes": "string or null - athlete feedback from results",
                    "coachNotes": "string or null - full prescription text from plan",
                    "displayOrder": 0,
                    "sets": [
                        {
                            "completed": true,
                            "reps": 8,
                            "load": 225.0,
                            "unit": "lb",
                            "rir": 2,
                            "notes": "string or null",
                            "targetReps": "8-10",
                            "targetLoad": "220-230 lb",
                            "targetRir": "2-3",
                            "displayOrder": 0
                        }
                    ]
                }
            ],
            "cardioWorkouts": [
                {
                    "name": "string",
                    "modality": "rowing|spinning|running",
                    "notes": "string or null - athlete feedback",
                    "coachNotes": "string or null - full prescription from plan",
                    "displayOrder": 0,
                    "intervals": [
                        {
                            "completed": true,
                            "durationSec": 1800,
                            "distanceM": 6000,
                            "paceSecPerKm": 300,
                            "cadence": 90,
                            "strokeRateSpm": 24,
                            "powerW": 180,
                            "avgHeartRate": 145,
                            "avgPowerW": 175,
                            "calories": 350,
                            "perceivedEffort": 6,
                            "notes": "string or null",
                            "targetDuration": "30:00",
                            "targetDistance": "6000m",
                            "targetPace": "2:00/500m",
                            "targetCadence": "20-22 spm",
                            "targetHeartRate": "Z2 (115-125bpm)",
                            "targetPower": "170-180W",
                            "displayOrder": 0
                        }
                    ]
                }
            ],
            "yogaMobility": {
                "title": "string or null",
                "durationMin": 30,
                "focusAreas": ["hips", "spine"],
                "notes": "string or null",
                "coachNotes": "string or null",
                "targetDuration": "30 min",
                "movements": [
                    {
                        "name": "Pigeon Pose",
                        "reps": 3,
                        "completed": true,
                        "displayOrder": 0
                    }
                ]
            }
        }
        ```

        ## Mapping Instructions:

        ### 1. MOST IMPORTANT - Populate Target Fields from Plan:
           - Extract ALL prescription details from the structured workout plan
           - For rowing: look for stroke rate (spm), pace, distance, duration, heart rate zones
           - For strength: look for reps, load/weight, RIR (reps in reserve)
           - For running/spinning: look for pace, cadence, heart rate, power
           - Include units and ranges in target strings: "8-10 reps", "Z2 (115-125bpm)", "20-22 spm"
           - If the plan says "Z2 row" or "Zone 2", set targetHeartRate to "Z2 (115-125bpm)"
           - If the plan mentions stroke rate like "20 spm", set targetCadence to "20 spm"

        ### 2. Populate Actual Fields from Logged Results:
           - Match logged results to exercises by name (fuzzy match OK)
           - Only populate actual fields (reps, load, durationSec, etc.) if there are logged results
           - Set completed=true for items with logged results
           - Leave actual fields null/omitted if no results were logged

        ### 3. Exercise Type Mapping:
           - "strength" or exercises with sets/reps/weight → strengthExercises
           - "cardio*", "row*", "bike*", "run*", "spin*" → cardioWorkouts
           - "yoga*", "mobility*", "stretch*" → yogaMobility

        ### 4. Modality Detection:
           - primaryModality: main focus of the day
           - cardio modality: "row*" → "rowing", "bike*"/"spin*" → "spinning", "run*" → "running"

        ### 5. Coach Notes:
           - coachNotes: Put the FULL prescription text from the plan here
           - Include all details: sets, reps, rest periods, intensity notes, etc.
           - Example: "3x8-10 @ RPE 7-8, 90s rest between sets"

        ### 6. Athlete Notes:
           - notes: Put feedback from logged results here
           - How it felt, any issues, observations

        ### 7. Weight Handling:
           - Convert all weights to lb (multiply kg by 2.205)
           - Always use unit: "lb"

        ### 8. Time/Distance Conversion:
           - durationSec: convert time strings to seconds
           - distanceM: convert to meters
           - paceSecPerKm: convert pace to seconds per km

        ### 9. Empty Sections:
           - Omit strengthExercises if no strength work
           - Omit cardioWorkouts if no cardio work
           - Omit yogaMobility if no yoga/mobility work

        ## Examples of Good Target Field Values:
        - targetHeartRate: "Z2 (115-125bpm)", "Zone 3 (140-155bpm)", "130-145bpm"
        - targetCadence: "20-22 spm" (rowing), "85-95 rpm" (cycling), "170-180 spm" (running)
        - targetPace: "2:00/500m" (rowing), "8:00/mile" (running)
        - targetReps: "8-10", "5", "AMRAP"
        - targetLoad: "185-205 lb", "bodyweight", "RPE 7-8"
        - targetRir: "2-3", "1", "0 (failure)"
        - targetDuration: "30:00", "20-25 min"
        - targetDistance: "6000m", "5k"
        - targetPower: "170-180W", "Zone 3"

        Output ONLY valid JSON. No explanation or markdown.
        """
    }
    
    // MARK: - LLM Communication
    
    private func callLLM(prompt: String) async throws -> String {
        let apiKey = AppConfiguration.shared.apiKey
        guard !apiKey.isEmpty else {
            throw MappingError.missingAPIKey
        }
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("TrainerApp", forHTTPHeaderField: "X-Title")
        request.addValue("com.trainerapp.ios", forHTTPHeaderField: "HTTP-Referer")
        request.timeoutInterval = 60.0
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.1  // Low temperature for consistent mapping
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        #if DEBUG
        print("🤖 LLM Request to \(model) (\(prompt.count) chars)")
        #endif
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MappingError.llmError("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to extract error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw MappingError.llmError(message)
            }
            throw MappingError.llmError("HTTP \(httpResponse.statusCode)")
        }
        
        let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
        
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw MappingError.invalidResponse
        }
        
        #if DEBUG
        print("🤖 LLM Response (\(content.count) chars)")
        #endif
        
        return content
    }
    
    // MARK: - Response Parsing
    
    private func parseMappingResponse(_ response: String) throws -> MappedDayData {
        // Clean up response - remove potential markdown code blocks
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = String(cleanedResponse.dropFirst(7))
        }
        if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3))
        }
        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3))
        }
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw MappingError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(MappedDayData.self, from: data)
        } catch let decodingError {
            print("❌ Failed to decode LLM response: \(decodingError)")
            print("📝 Response was: \(cleanedResponse.prefix(500))...")
            throw MappingError.invalidResponse
        }
    }
}

// MARK: - LLM Response Types

private struct LLMResponse: Decodable {
    let choices: [LLMChoice]
}

private struct LLMChoice: Decodable {
    let message: LLMMessage
}

private struct LLMMessage: Decodable {
    let content: String?
}

// MARK: - Mapping Errors

enum MappingError: LocalizedError {
    case missingAPIKey
    case llmError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key not configured. Set it in Settings."
        case .llmError(let message):
            return "Failed to map workout data: \(message)"
        case .invalidResponse:
            return "Invalid mapping response. Please try again."
        }
    }
}
