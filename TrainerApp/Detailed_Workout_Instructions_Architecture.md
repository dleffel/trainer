# Detailed Workout Instructions Architecture

## Overview
This document outlines the architecture for storing and displaying detailed workout instructions in a structured way within the calendar, with the coach providing links in chat to keep conversations clean.

## Data Model Changes

### 1. Extend WorkoutDay Model
```swift
struct WorkoutDay: Codable, Identifiable {
    // Existing fields...
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    let plannedWorkout: String?
    var completed: Bool = false
    var notes: String?
    var actualWorkout: String?
    
    // New field for detailed instructions
    var detailedInstructions: WorkoutInstructions?
}

struct WorkoutInstructions: Codable {
    let id = UUID()
    let generatedAt: Date
    let sections: [InstructionSection]
    
    // Quick access to formatted text for display
    var formattedText: String {
        sections.map { $0.formattedContent }.joined(separator: "\n\n")
    }
}

struct InstructionSection: Codable {
    enum SectionType: String, Codable {
        case overview = "Overview"
        case heartRateZones = "Heart Rate Zones"
        case warmUp = "Warm-up"
        case mainSet = "Main Set"
        case coolDown = "Cool-down"
        case technique = "Technique Focus"
        case hydration = "Hydration"
        case nutrition = "Nutrition"
        case recovery = "Recovery"
        case alternatives = "Alternative Options"
        case notes = "Additional Notes"
    }
    
    let type: SectionType
    let title: String
    let content: [String] // Array for bullet points or paragraphs
    
    var formattedContent: String {
        var result = "## \(title)\n"
        result += content.map { "• \(text)" }.joined(separator: "\n")
        return result
    }
}
```

## Tool Implementation

### 2. New Tool: generate_workout_instructions
```swift
// In ToolProcessor.swift
case "generate_workout_instructions":
    let dateParam = toolCall.parameters["date"] as? String ?? "today"
    let result = try await executeGenerateWorkoutInstructions(date: dateParam)
    return ToolCallResult(toolName: toolCall.name, result: result)

private func executeGenerateWorkoutInstructions(date: String) async throws -> String {
    // Get the workout day
    let targetDate = parseDate(date)
    guard let workoutDay = manager.getWorkoutDay(for: targetDate) else {
        return "[Instructions: No workout found for \(formatDate(targetDate))]"
    }
    
    // Generate instructions based on workout type and context
    let instructions = generateInstructionsForWorkout(workoutDay)
    
    // Save to the workout day
    var updatedDay = workoutDay
    updatedDay.detailedInstructions = instructions
    manager.updateWorkoutDay(updatedDay)
    
    // Return confirmation with link format
    return """
    [Detailed Instructions Generated]
    • Date: \(formatDate(targetDate))
    • Workout: \(workoutDay.plannedWorkout ?? "Custom")
    
    View in calendar: [trainer://calendar/\(targetDate.ISO8601Format())]
    """
}
```

## UI Components

### 3. Enhanced WorkoutDetailSheet
```swift
struct WorkoutDetailSheet: View {
    // Existing properties...
    @State private var showingInstructions = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Existing header...
                
                // New: Detailed Instructions Section
                if let instructions = day.detailedInstructions {
                    DetailedInstructionsCard(
                        instructions: instructions,
                        isExpanded: $showingInstructions
                    )
                }
                
                // Existing planned workout...
                // Existing actual workout...
                // Existing notes...
            }
        }
    }
}

struct DetailedInstructionsCard: View {
    let instructions: WorkoutInstructions
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Detailed Instructions", systemImage: "doc.text.fill")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }
            
            if isExpanded {
                ForEach(instructions.sections, id: \.type) { section in
                    InstructionSectionView(section: section)
                }
            } else {
                Text("Tap to view detailed workout instructions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InstructionSectionView: View {
    let section: InstructionSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            ForEach(section.content, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(item)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

## Deep Linking

### 4. URL Scheme Implementation
```swift
// In TrainerAppApp.swift
@main
struct TrainerAppApp: App {
    @StateObject private var navigationState = NavigationState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // trainer://calendar/2024-01-15
        guard url.scheme == "trainer",
              url.host == "calendar",
              let dateString = url.pathComponents.last,
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return
        }
        
        navigationState.navigateToWorkoutDay(date: date)
    }
}

class NavigationState: ObservableObject {
    @Published var selectedTab = 0
    @Published var targetWorkoutDate: Date?
    @Published var showCalendar = false
    
    func navigateToWorkoutDay(date: Date) {
        targetWorkoutDate = date
        selectedTab = 1 // Calendar tab
        showCalendar = true
    }
}
```

## Visual Indicators

### 5. Calendar Day Card Enhancement
```swift
struct DayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // Existing content...
            
            // New: Instructions indicator
            if day.detailedInstructions != nil {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
        }
        // Rest of implementation...
    }
}
```

## Coach Integration

### 6. System Prompt Addition
Add to the coach's system prompt:
```
When providing detailed workout instructions:
1. Use [TOOL_CALL: generate_workout_instructions(date: "YYYY-MM-DD")] to create structured instructions
2. The tool will save instructions to the calendar and return a clickable link
3. Include only relevant sections based on the workout type:
   - Endurance workouts: Include HR zones, hydration, pacing
   - Strength workouts: Include sets/reps, rest periods, technique cues
   - Recovery days: Include mobility work, recovery nutrition
4. Keep the chat message brief - just mention you've created detailed instructions with the link
```

## Example Workflow

1. **User asks about today's workout**
2. **Coach generates instructions:**
   ```
   I'll create detailed instructions for today's spin bike session.
   [TOOL_CALL: generate_workout_instructions(date: "today")]
   ```
3. **Coach sends message:**
   ```
   I've prepared detailed instructions for your 60-minute easy spin bike session, 
   including HR zones, warm-up protocol, and mobility work.
   
   📋 View instructions: trainer://calendar/2024-01-15
   ```
4. **User clicks link** → Opens calendar → Shows workout day with expanded instructions

## Benefits

1. **Clean Chat**: Detailed instructions don't clutter the conversation
2. **Structured Storage**: Instructions are saved with the workout for future reference
3. **Flexible Detail**: Coach determines what sections to include based on workout type
4. **Easy Access**: One-click navigation from chat to full instructions
5. **Visual Indicators**: Users can see which days have detailed instructions at a glance