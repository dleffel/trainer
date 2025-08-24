# Apple Health Integration Plan for TrainerApp

## Overview
This plan outlines how to integrate Apple Health data into the TrainerApp so that the AI coach can access user health metrics (Weight, Time Asleep, Body Fat %, Lean Body Mass, Height) through a tool-calling mechanism instead of prompting the user directly.

## Current State Analysis
- The app uses OpenAI's chat completion API with a system prompt from `SystemPrompt.md`
- Currently, the system prompt is hardcoded in ContentView.swift (not actually loading from the file)
- The AI interacts through standard chat messages without tool-calling capabilities

## Implementation Plan

### Phase 1: Apple HealthKit Integration

1. **Add HealthKit Capability**
   - Add HealthKit capability to the app's entitlements
   - Update Info.plist with health data usage descriptions
   - Request authorization for reading specific health data types

2. **Create HealthKit Manager**
   - Build a `HealthKitManager` class to handle:
     - Authorization requests
     - Data queries for: Weight, Sleep Analysis, Body Fat %, Lean Body Mass, Height
     - Error handling and data availability checks

3. **Data Models**
   - Create Swift structs to represent health data:
     ```swift
     struct HealthData {
         var weight: Double? // kg
         var timeAsleepHours: Double?
         var bodyFatPercentage: Double?
         var leanBodyMass: Double? // kg
         var height: Double? // meters
         var lastUpdated: Date
     }
     ```

### Phase 2: Tool Calling Implementation

1. **Modify System Prompt**
   - Update SystemPrompt.md to include tool availability
   - Add instructions for when and how to use the health data tool
   - Example addition:
     ```
     AVAILABLE TOOLS:
     
     get_health_data - Retrieves the user's latest health metrics from Apple Health
     Returns: weight (lb), timeAsleepHours, bodyFatPercentage, leanBodyMass (lb), height (ft-in)
     Use this tool instead of asking the user for these metrics.
     ```

2. **Implement Tool Calling Protocol**
   - Extend the chat message structure to support tool calls
   - Create a response format that includes tool requests:
     ```json
     {
       "tool_call": "get_health_data",
       "parameters": {}
     }
     ```

3. **Message Processing Enhancement**
   - Modify the message handling to:
     - Detect tool call requests in AI responses
     - Execute the health data fetch
     - Inject the results back into the conversation
     - Continue with the AI's response using the fetched data

### Phase 3: System Prompt Loading

1. **Fix System Prompt Loading**
   - Implement actual file loading for SystemPrompt.md
   - Add file monitoring for development updates
   - Handle file loading errors gracefully

### Phase 4: UI/UX Considerations

1. **Permission Flow**
   - Create onboarding screen for HealthKit permissions
   - Show clear explanations of why each data type is needed
   - Handle permission denial gracefully

2. **Data Visibility**
   - Add indicator when health data is being fetched
   - Show last sync time for transparency
   - Allow manual refresh of health data

### Technical Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   ContentView   │────▶│  ChatViewModel   │────▶│   LLMClient     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │                           │
                               ▼                           ▼
                        ┌──────────────────┐     ┌─────────────────┐
                        │ HealthKitManager │     │ Tool Processor  │
                        └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │   HealthKit API  │
                        └──────────────────┘
```

### Implementation Steps

1. **Step 1**: Create HealthKitManager and test basic data fetching
2. **Step 2**: Update entitlements and Info.plist
3. **Step 3**: Implement system prompt file loading
4. **Step 4**: Add tool calling detection to message processing
5. **Step 5**: Create tool execution logic
6. **Step 6**: Update system prompt with tool instructions
7. **Step 7**: Add UI for permissions and data status
8. **Step 8**: Test end-to-end flow

### Testing Strategy

1. **Unit Tests**
   - HealthKit data parsing
   - Tool call detection
   - Message formatting with tool results

2. **Integration Tests**
   - Full flow from AI request to data injection
   - Permission handling
   - Error scenarios (no data, denied permissions)

3. **Manual Testing**
   - Various health data scenarios
   - Permission flows
   - AI understanding of available tools

### Security & Privacy

1. **Data Handling**
   - Only fetch data when explicitly requested by AI
   - Don't persist health data unnecessarily
   - Clear data on logout/app reset

2. **Permissions**
   - Request only read permissions
   - Explain data usage clearly
   - Respect user's privacy choices

### Future Enhancements

1. **Additional Health Metrics**
   - Resting heart rate
   - VO2 max
   - Activity data

2. **Historical Data**
   - Trends and averages
   - Progress tracking
   - Anomaly detection

3. **Tool Extensions**
   - Multiple tool support
   - Parameter-based queries (e.g., date ranges)
   - Calculated metrics

## Next Steps

1. Review and approve this plan
2. Switch to code mode for implementation
3. Start with HealthKit integration (Phase 1)
4. Incrementally add tool calling capabilities