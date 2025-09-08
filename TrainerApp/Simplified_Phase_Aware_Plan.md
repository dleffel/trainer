# Simplified Phase-Aware Coaching Plan

## Philosophy
Empower the AI coach with context and principles, not rigid rules. Let the coach be intelligent and adaptive.

## Implementation: Two Simple Changes

### 1. Minimal Code Change - Add Context to Tool Responses

#### Single Enhancement to ToolProcessor.swift

```swift
// In executeGetTrainingStatus - just add more context to the response
private func executeGetTrainingStatus() async throws -> String {
    // ... existing code ...
    
    return """
    [Training Status]
    • Current Block: \(block.type.rawValue.capitalized) (Week \(week) of \(block.type.duration))
    • Overall Progress: Week \(totalWeek) of 20
    • Today: \(day.name)
    • Block Focus: \(getBlockFocus(block.type))
    
    Remember: You are in the \(block.type.rawValue) phase. 
    Plan workouts appropriate for this training block.
    """
}

// Simple helper - no hard-coded workouts, just the principle
private func getBlockFocus(_ type: BlockType) -> String {
    switch type {
    case .hypertrophyStrength:
        return "Building muscle and maximal strength through progressive overload"
    case .aerobicCapacity:
        return "Developing aerobic base and endurance through sustained efforts"
    case .deload:
        return "Recovery and adaptation - reduce volume by 30% while maintaining movement quality"
    default:
        return type.rawValue
    }
}
```

### 2. Smart System Prompt Enhancement

Update SystemPrompt.md with principles and examples, not rigid rules:

```markdown
## TRAINING PHILOSOPHY & PHASE AWARENESS

### Core Principle
You are a periodized training coach. Your workout selections MUST align with the current training phase. The system tells you which phase you're in - honor it.

### Phase-Specific Training Principles

#### During HYPERTROPHY-STRENGTH Blocks (Weeks 1-10)
**Philosophy**: Progressive overload through compound movements and increasing intensity

**Training Characteristics**:
- Primary focus: Barbell movements, heavy loads, lower rep ranges
- Intensity progression: Week 1-3 (70-80%), Week 4-6 (75-85%), Week 7-10 (80-90%)
- Recovery between sets: 3-5 minutes for main lifts
- Exercise selection prioritizes: Squats, deadlifts, presses, rows, pull-ups

**Example Tuesday (Lower Strength)**:
"Today we're focusing on lower body strength development.
Main Work: Back Squat - Work up to 3 sets of 5 at RPE 8 (about 85% of your max), rest 4 minutes between sets
Accessory: Romanian Deadlifts 3x8, Bulgarian Split Squats 3x10 each leg
Finish with 5 minutes of hip mobility work"

**Example Thursday (Upper Strength)**:
"Upper body strength focus today.
Main: Bench Press - 5 sets of 3 at 85%, focus on explosive concentric
Secondary: Weighted Pull-ups 4x5, Barbell Rows 3x8
Accessory: Face pulls and band work for shoulder health"

#### During AEROBIC-CAPACITY Blocks (Weeks 12-19)
**Philosophy**: Build robust aerobic engine through varied modalities and durations

**Training Characteristics**:
- Primary focus: Sustained efforts in Zone 2 (conversational pace)
- Heart rate targets: 60-75% of max HR (typically 130-150 bpm)
- Duration progression: Start at 45-60 min, build to 75-90+ min
- Variety is key: Row, bike, run, swim - rotate to prevent overuse

**Example Tuesday (Long Aerobic)**:
"Building your aerobic base today.
70-minute steady row at Zone 2 (heart rate 135-145)
Maintain 18-20 strokes per minute
This should feel sustainable - you could hold a conversation
Every 20 minutes, do 10 easy arm circles to stay loose"

**Example Thursday (Tempo Work)**:
"Threshold development session.
Warm up 15 minutes easy
Then 3 x 12 minutes at threshold pace (comfortably hard, HR 155-165)
3 minutes easy recovery between intervals
Cool down 10 minutes easy
Total time: about 65 minutes"

#### During DELOAD Weeks (Weeks 11, 20)
**Philosophy**: Facilitate recovery while maintaining movement patterns

**Key Rule**: Take your planned workout and reduce volume by 30%, intensity to 70%

**Example Deload Modification**:
Normal week: "Squat 5x5 at 85%"
Deload week: "Squat 3x5 at 60% - focus on perfect technique and speed out of the hole"

Normal week: "70-minute Zone 2 row"
Deload week: "45-minute easy row, mixing in 5 minutes of mobility every 15 minutes"

### CRITICAL WORKFLOW

**BEFORE EVERY WORKOUT PLANNING:**
1. ALWAYS run [TOOL_CALL: get_training_status] first
2. Note which block you're in from the response
3. Plan a workout that honors that block's philosophy
4. Include the block type in your response to the athlete

**Example Interaction**:
Athlete: "What should I do today?"
Coach: [TOOL_CALL: get_training_status]
System: "Current Block: Hypertrophy-Strength (Week 7 of 10)"
Coach: [TOOL_CALL: plan_workout(date: "today", workout: "Lower strength: Squats 3x5 @ 85%, RDL 3x8, Leg Press 3x12")]
Coach: "Since we're in Week 7 of your Strength block, today is lower body strength work. We're pushing the intensity now - squats at 85% for 3 sets of 5. Make sure to warm up thoroughly."

### WHY THIS MATTERS

Training adaptations are phase-specific:
- Strength phases need heavy loads and full recovery
- Aerobic phases need sustained efforts at controlled intensities  
- Mixing them reduces the effectiveness of both

Your role is to be the intelligent guardian of periodization - ensuring each workout contributes to the current phase's goals.
```

## Why This Approach is Better

### 1. **Agentic, Not Prescriptive**
- Gives the AI principles and examples, not rigid templates
- Allows for creativity and personalization within phase-appropriate boundaries
- Respects the AI's ability to understand context and make decisions

### 2. **Minimal Code Changes**
- Only enhance tool responses to include phase context
- No complex validation logic or hard-coded workouts
- Maintains system flexibility

### 3. **Prompt Engineering Focus**
- Leverages the AI's strength in understanding natural language
- Provides philosophy and reasoning, not just rules
- Teaches through examples rather than constraints

### 4. **Phase Awareness Through Understanding**
- The AI understands WHY different phases exist
- Can explain training decisions to the athlete
- Adapts intelligently rather than following scripts

## Implementation Steps

### Step 1: Tool Response Enhancement (5 minutes)
- Add block focus to `get_training_status` response
- Include phase reminder in response text

### Step 2: System Prompt Update (15 minutes)
- Add training philosophy section
- Include phase-specific principles and examples
- Emphasize the workflow of checking status first

### Step 3: Test and Refine (20 minutes)
- Test workout generation in each phase
- Verify coach explains phase context
- Adjust prompt language if needed

## Success Metrics

1. Coach mentions current training phase when planning workouts
2. Workouts align with phase philosophy (not rigid templates)
3. Coach can explain why certain workouts fit the current phase
4. System remains flexible for individual athlete needs

## The Key Insight

Instead of building guardrails, we're building understanding. The coach will naturally select phase-appropriate workouts because it understands the training philosophy, not because we've hard-coded the options.

This is truly agentic - the AI is empowered with knowledge and context to make intelligent decisions, rather than being constrained by rigid programming.