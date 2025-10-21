# Workout Log UI Refactoring Plan

## Overview

This plan addresses critical UX issues in the workout logging interface while maintaining simplicity and code maintainability. The focus is on realigning the information architecture with the user's jobs-to-be-done framework.

## Core Principles

1. **Simplicity First**: Leverage existing SwiftUI components, avoid over-engineering
2. **Maintainability**: Create small, focused, reusable components
3. **Jobs-to-Be-Done**: Optimize for the top 3 user jobs (85% of use cases)
4. **Progressive Enhancement**: Implement in priority order with measurable improvements

## Priority Matrix

| Priority | Issue | Impact | Effort | Risk | Order |
|----------|-------|--------|--------|------|-------|
| 🔴 Critical | Reorganize workout hierarchy | High | Medium | Low | 1 |
| 🔴 Critical | Add program context to workout view | High | Low | Low | 2 |
| 🟡 Important | Improve coaching notes presentation | Medium | Low | Low | 3 |
| 🟡 Important | Add during-workout navigation | Medium | Medium | Medium | 4 |
| 🟢 Nice-to-Have | Clarify view navigation | Low | Low | Low | 5 |
| 🟢 Nice-to-Have | Accessibility enhancements | Medium | Medium | Low | 6 |

---

## Phase 1: Information Architecture Fixes (Critical)

### 1.1 Reorganize Workout Detail Hierarchy

**Current State** (WeeklyCalendarView.swift:613-700):
```
StructuredWorkoutView:
  ├─ Workout Header (title, duration, notes) ← 320-380px coaching notes
  ├─ Exercise Navigation
  └─ Exercise TabView
```

**Target State**:
```
StructuredWorkoutView:
  ├─ Workout Summary (title, duration, chips)     ← ~100px
  ├─ Exercise TabView (primary content)           ← ~280px
  ├─ Coaching Notes (collapsible, default closed) ← 40px collapsed
  └─ [Same exercise navigation]
```

**Implementation**:

1. **Create new `WorkoutSummaryView` component**:
```swift
// TrainerApp/TrainerApp/Views/Workout/WorkoutSummaryView.swift
struct WorkoutSummaryView: View {
    let title: String?
    let duration: Int?
    let rpe: String?
    let modality: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.title3.bold())
            }
            
            // Horizontal chip layout for key stats
            HStack(spacing: 8) {
                if let duration = duration {
                    Chip(icon: "clock", text: "\(duration) min", color: .blue)
                }
                if let rpe = rpe {
                    Chip(icon: "flame", text: rpe, color: .orange)
                }
                if let modality = modality {
                    Chip(icon: workoutIcon(for: modality), text: modality, color: .purple)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(12)
    }
}
```

2. **Create new `CoachingNotesView` component**:
```swift
// TrainerApp/TrainerApp/Views/Workout/CoachingNotesView.swift
struct CoachingNotesView: View {
    let notes: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                    Text("Coaching Notes")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.secondary)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
            .accessibilityLabel("Coaching notes")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
            
            if isExpanded {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
        }
    }
}
```

3. **Refactor `StructuredWorkoutView`** (WeeklyCalendarView.swift:613):
```swift
var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        // NEW: Compact summary replaces verbose header
        WorkoutSummaryView(
            title: workout.title,
            duration: workout.totalDuration,
            rpe: extractRPE(from: workout.notes),
            modality: extractModality(from: workout.notes)
        )
        
        // Exercise navigation and TabView (unchanged)
        if count > 1 {
            // ... existing navigation code
        }
        
        TabView(selection: $selectedExerciseIndex) {
            // ... existing TabView code
        }
        
        // NEW: Coaching notes moved to bottom, collapsible
        if let notes = workout.notes {
            CoachingNotesView(notes: notes)
        }
    }
}
```

**Files to Create**:
- `TrainerApp/TrainerApp/Views/Workout/WorkoutSummaryView.swift`
- `TrainerApp/TrainerApp/Views/Workout/CoachingNotesView.swift`

**Files to Modify**:
- `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift` (lines 613-700)

**Estimated Impact**:
- Time to workout context: 3.5s → 0.8s (77% improvement)
- Job 1 score: 5/10 → 9/10
- Job 2 score: 4/10 → 7/10

---

### 1.2 Add Program Context to Workout View

**Current State**: Block info card only appears in calendar view (WeeklyCalendarView.swift:160-222)

**Target State**: Condensed program context in workout detail header

**Implementation**:

1. **Create `ProgramContextBanner` component**:
```swift
// TrainerApp/TrainerApp/Views/Workout/ProgramContextBanner.swift
struct ProgramContextBanner: View {
    let blockType: BlockType
    let weekNumber: Int
    let totalWeeks: Int
    let daysToDeload: Int?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: blockType.icon)
                .font(.caption)
                .foregroundStyle(blockGradient(for: blockType))
            
            Text("Week \(weekNumber)/\(totalWeeks)")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            Text("•")
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(blockType.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let days = daysToDeload, days > 0 {
                Spacer()
                Text("\(days)d to deload")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func blockGradient(for type: BlockType) -> LinearGradient {
        // ... same gradient logic from blockInfoCard
    }
}
```

2. **Modify `WorkoutDetailsCard`** (WeeklyCalendarView.swift:504):
```swift
var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        // Header with day info
        HStack(spacing: 12) {
            // ... existing icon and day info
            
            Spacer()
            
            Button {
                // ... existing collapse logic
            } label: {
                // ... existing chevron
            }
        }
        
        // NEW: Add program context banner below header
        if let block = scheduleManager.getBlockForDate(day.date),
           let program = scheduleManager.currentProgram {
            let weekNumber = calculateWeekNumber(for: day.date, program: program)
            let daysToDeload = calculateDaysUntilDeload(from: day.date, block: block)
            
            ProgramContextBanner(
                blockType: block.type,
                weekNumber: weekNumber,
                totalWeeks: block.type.duration,
                daysToDeload: daysToDeload
            )
        }
        
        // ... rest of existing content
    }
}
```

**Files to Create**:
- `TrainerApp/TrainerApp/Views/Workout/ProgramContextBanner.swift`

**Files to Modify**:
- `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift` (lines 504-609)

**Estimated Impact**:
- Job 5 score: 6/10 → 8/10
- Reduces context switching between views

---

## Phase 2: Interaction Improvements (Important)

### 2.1 Improve Coaching Notes Presentation

**Already addressed in Phase 1.1** with `CoachingNotesView` component.

Additional enhancement:

**Add "Read More" truncation for extra-long notes**:
```swift
struct CoachingNotesView: View {
    let notes: String
    @State private var isExpanded = false
    
    private var shouldTruncate: Bool {
        notes.count > 200 // Threshold for truncation
    }
    
    private var displayText: String {
        if shouldTruncate && !isExpanded {
            return String(notes.prefix(200)) + "..."
        }
        return notes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header button (same as before)
            
            if isExpanded || !shouldTruncate {
                Text(displayText)
                    .font(.subheadline)
                    // ... styling
                
                if shouldTruncate {
                    Button("Read Less") {
                        withAnimation { isExpanded = false }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
}
```

---

### 2.2 Add During-Workout Navigation

**Goal**: Make it effortless to move between exercises during active workout.

**Implementation**:

1. **Create `WorkoutModeOverlay` component**:
```swift
// TrainerApp/TrainerApp/Views/Workout/WorkoutModeOverlay.swift
struct WorkoutModeOverlay: View {
    let currentExercise: Int
    let totalExercises: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 16) {
                // Previous button
                if currentExercise > 0 {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onPrevious()
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(24)
                    }
                    .accessibilityLabel("Previous exercise")
                }
                
                Spacer()
                
                // Next button (larger, more prominent)
                if currentExercise < totalExercises - 1 {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onNext()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(28)
                            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .accessibilityLabel("Next exercise")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24) // Above tab bar
        }
    }
}
```

2. **Add workout mode state to `WorkoutDetailsCard`**:
```swift
@State private var isWorkoutMode = false

var body: some View {
    ZStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 16) {
            // ... existing content
        }
        .padding(20)
        .background(/* ... existing styling ... */)
        
        // NEW: Overlay for workout mode
        if isWorkoutMode, let structuredWorkout = day.structuredWorkout {
            WorkoutModeOverlay(
                currentExercise: selectedExerciseIndex,
                totalExercises: structuredWorkout.exercises.count,
                onNext: {
                    if selectedExerciseIndex < structuredWorkout.exercises.count - 1 {
                        selectedExerciseIndex += 1
                    }
                },
                onPrevious: {
                    if selectedExerciseIndex > 0 {
                        selectedExerciseIndex -= 1
                    }
                }
            )
        }
    }
}
```

3. **Add workout mode toggle**:
```swift
// In WorkoutDetailsCard header, add toggle button:
Button {
    withAnimation {
        isWorkoutMode.toggle()
    }
} label: {
    Image(systemName: isWorkoutMode ? "stop.circle.fill" : "play.circle.fill")
        .font(.system(size: 24))
        .foregroundStyle(isWorkoutMode ? .red.gradient : .green.gradient)
}
.accessibilityLabel(isWorkoutMode ? "Exit workout mode" : "Start workout mode")
```

**Alternative Approach** (simpler):
Instead of a full "workout mode," enhance the existing TabView swipe gesture:
- Add larger chevrons that appear on tap (fade out after 3 seconds)
- Increase swipe sensitivity for TabView
- Add haptic feedback on page change

```swift
// Simpler enhancement to existing StructuredWorkoutView:
TabView(selection: $selectedExerciseIndex) {
    // ... existing content
}
.onChange(of: selectedExerciseIndex) { _, _ in
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
}
```

**Recommendation**: Start with the simpler approach (enhanced gestures), add workout mode overlay only if user testing shows need.

**Files to Create** (full approach):
- `TrainerApp/TrainerApp/Views/Workout/WorkoutModeOverlay.swift`

**Files to Modify**:
- `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift` (WorkoutDetailsCard and StructuredWorkoutView)

**Estimated Impact**:
- Job 2 score: 7/10 → 9/10 (with full approach)
- Job 2 score: 7/10 → 8/10 (with simple approach)

---

## Phase 3: Polish & Accessibility (Nice-to-Have)

### 3.1 Clarify View Navigation

**Current Issue**: Unclear how users transition between calendar view and workout detail.

**Simple Solution**:

1. **Add navigation indicator to selected day card**:
```swift
// In DayCard (WeeklyCalendarView.swift:369), enhance tap target:
.onTapGesture {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        selectedDay = day
    }
}
.accessibilityHint("Double tap to view workout details below") // Added hint
```

2. **Add scroll-to-detail animation**:
```swift
// In WeeklyCalendarView, when day is selected:
@Namespace private var detailSection

var body: some View {
    ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                // ... week selector and block info
                
                weekGrid
                
                if let day = selectedDay {
                    Divider()
                        .padding(.vertical, 8)
                    
                    WorkoutDetailsCard(day: day, scheduleManager: scheduleManager)
                        .id("workout-detail") // Add ID
                        .transition(/* ... existing transition ... */)
                }
            }
            .padding(16)
        }
        .onChange(of: selectedDay) { _, newValue in
            if newValue != nil {
                withAnimation {
                    proxy.scrollTo("workout-detail", anchor: .top)
                }
            }
        }
    }
}
```

**Files to Modify**:
- `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift` (lines 32-113, 369-431)

---

### 3.2 Accessibility Enhancements

**Implementation**:

1. **Add semantic structure to coaching notes**:
```swift
// In CoachingNotesView:
Text(notes)
    .accessibilityAddTraits(.isHeader) // Mark as heading
    .accessibilityLabel("Coaching notes: \(notes)")
```

2. **Improve exercise navigation accessibility**:
```swift
// In StructuredWorkoutView exercise navigation:
HStack(spacing: 8) {
    Button {
        if selectedExerciseIndex > 0 { selectedExerciseIndex -= 1 }
    } label: {
        Image(systemName: "chevron.left")
            .frame(width: 44, height: 44) // Larger touch target
    }
    .disabled(selectedExerciseIndex == 0)
    .accessibilityLabel("Previous exercise")
    .accessibilityValue("Exercise \(selectedExerciseIndex) of \(count)")
    
    // ... rest of navigation
}
```

3. **Add zone badges with text labels** (fix color-only reliance):
```swift
// In IntervalRow or CardioExerciseView:
HStack(spacing: 4) {
    Text("Z\(zone)")
        .font(.caption2.bold())
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(zoneColor(for: zone))
        .cornerRadius(4)
    
    Text(rpmRange)
        .font(.caption)
        .foregroundColor(.secondary)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Zone \(zone), \(rpmRange)")
```

**Files to Modify**:
- `TrainerApp/TrainerApp/Views/Workout/CoachingNotesView.swift`
- `TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift` (StructuredWorkoutView, IntervalRow, CardioExerciseView)

---

## Component Organization

Create new directory structure for better maintainability:

```
TrainerApp/TrainerApp/Views/Workout/
├── WorkoutSummaryView.swift       (new)
├── CoachingNotesView.swift        (new)
├── ProgramContextBanner.swift     (new)
├── WorkoutModeOverlay.swift       (new, optional)
└── Components/
    ├── ExerciseCard.swift         (extracted from WeeklyCalendarView)
    ├── CardioExerciseView.swift   (extracted)
    ├── StrengthExerciseView.swift (extracted)
    └── IntervalRow.swift          (extracted)
```

**Refactoring Strategy**:
1. Create new components in Workout directory
2. Import into WeeklyCalendarView
3. Remove duplicated code from WeeklyCalendarView
4. Update Xcode project to include new directory

---

## Implementation Sequence

### Iteration 1: Core Hierarchy Fix (2-3 hours)
**Goal**: Reorganize content to prioritize workout structure

1. Create `WorkoutSummaryView.swift`
2. Create `CoachingNotesView.swift`
3. Refactor `StructuredWorkoutView` in WeeklyCalendarView
4. Test: Measure time-to-workout-context, verify coaching notes expand/collapse

**Success Criteria**:
- Workout summary appears first (above fold)
- Coaching notes collapsed by default
- All existing functionality preserved

### Iteration 2: Program Context (1 hour)
**Goal**: Show program status in workout view

1. Create `ProgramContextBanner.swift`
2. Add to `WorkoutDetailsCard` header
3. Extract week calculation helpers
4. Test: Verify correct week/block info displays

**Success Criteria**:
- Program context visible in workout detail
- No performance impact (calculations are lightweight)

### Iteration 3: Navigation Enhancement (2-3 hours)
**Goal**: Improve during-workout flow

**Option A** (Simple - recommended first):
1. Add haptic feedback to TabView page changes
2. Enhance accessibility labels for exercise navigation
3. Add subtle visual hints for swipe gesture

**Option B** (Full):
1. Implement `WorkoutModeOverlay.swift`
2. Add workout mode toggle
3. Test interaction patterns

**Success Criteria**:
- Easy to navigate between exercises
- Clear feedback on exercise changes
- No accidental page changes during scrolling

### Iteration 4: Polish (1-2 hours)
**Goal**: Refine details and accessibility

1. Implement scroll-to-detail animation
2. Add accessibility improvements
3. Add zone badges with text
4. Test with VoiceOver

**Success Criteria**:
- VoiceOver users can navigate effectively
- All interactive elements have proper labels
- Color is not the only information indicator

---

## Testing Strategy

### Unit Testing
Not critical for UI components, but can add snapshot tests:
```swift
// TrainerApp/TrainerAppTests/WorkoutSummaryViewTests.swift
func testWorkoutSummaryLayout() {
    let summary = WorkoutSummaryView(
        title: "Z2 Spin Bike",
        duration: 60,
        rpe: "RPE 3-4",
        modality: "Bike"
    )
    // Snapshot test or view hierarchy validation
}
```

### Manual Testing Checklist

**Iteration 1**:
- [ ] Workout summary displays correctly
- [ ] Coaching notes collapse/expand with animation
- [ ] All workout types render (cardio, strength, mobility)
- [ ] Time to first exercise < 1 second
- [ ] Existing results section still works

**Iteration 2**:
- [ ] Program context shows correct week/block
- [ ] Days to deload calculates correctly
- [ ] Context appears for all workout types
- [ ] No performance degradation

**Iteration 3**:
- [ ] Exercise navigation feels natural
- [ ] Haptic feedback is appropriate
- [ ] TabView swipe works smoothly
- [ ] No conflicts with scroll gestures

**Iteration 4**:
- [ ] VoiceOver can navigate all elements
- [ ] Scroll-to-detail animation is smooth
- [ ] Zone badges are readable
- [ ] All accessibility labels are clear

### Regression Testing
- [ ] Week navigation still works
- [ ] Day selection still works
- [ ] Results logging still works
- [ ] Deep linking to workouts still works
- [ ] Program info card in calendar view unchanged

---

## Rollback Plan

Each iteration is independent and can be rolled back:

1. **Iteration 1 rollback**: Revert `StructuredWorkoutView` changes, keep old header
2. **Iteration 2 rollback**: Remove `ProgramContextBanner` from `WorkoutDetailsCard`
3. **Iteration 3 rollback**: Remove workout mode overlay or enhanced gestures
4. **Iteration 4 rollback**: Remove accessibility additions (shouldn't be needed)

**Key**: Commit after each successful iteration to enable easy rollback.

---

## Maintenance Considerations

### Code Organization
- **Keep components small**: Each component should have a single responsibility
- **Use composition**: Build complex views from simple components
- **Extract helpers**: Move calculation logic to manager extensions

### Performance
- **Lazy loading**: Exercise cards already use TabView (lazy)
- **Avoid expensive computations**: Cache week calculations
- **Monitor animation performance**: Use Instruments to check for jank

### Future Extensibility
This refactoring creates clean extension points:
- **New workout types**: Add to `WorkoutSummaryView` icon logic
- **Enhanced coaching**: Expand `CoachingNotesView` with rich media
- **Workout mode features**: Build on `WorkoutModeOverlay` foundation
- **Analytics**: Add tracking to workout mode interactions

---

## Metrics & Success Criteria

### Quantitative Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Time to workout context | ~3.5s | <1s | Manual timing with stopwatch |
| Taps to next exercise | 3-4 | 1-2 | Interaction recording |
| VoiceOver navigation time | Unknown | <5s | Accessibility testing |
| Coaching notes visibility | 100% | <30% default | Visual inspection |

### Qualitative Metrics
- User can quickly identify today's workout ✅
- User can follow along during workout ✅
- User understands program context ✅
- Interface feels natural and uncluttered ✅

### Jobs-to-Be-Done Scores

| Job | Current | Target | Post-Implementation |
|-----|---------|--------|---------------------|
| 1. Find today's workout | 5/10 | 9/10 | TBD |
| 2. Follow during workout | 4/10 | 9/10 | TBD |
| 3. Review logged results | 7/10 | 8/10 | TBD |
| 4. Review past workouts | 8/10 | 8/10 | 8/10 (no change) |
| 5. Understand program status | 6/10 | 8/10 | TBD |

**Target Weighted Average**: 8.7/10 (from current 5.35/10)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing functionality | Low | High | Comprehensive regression testing |
| Performance degradation | Low | Medium | Profile with Instruments before/after |
| User confusion with new layout | Medium | Medium | A/B test with users, easy rollback |
| Accessibility regression | Low | Medium | VoiceOver testing each iteration |
| Code complexity increase | Low | Low | Keep components small and focused |

---

## Dependencies & Prerequisites

### Code Dependencies
- ✅ Existing `Chip` component (WeeklyCalendarView.swift:1101)
- ✅ Existing `TrainingScheduleManager` methods
- ✅ Existing `WorkoutDay` and `StructuredWorkout` models
- ✅ No new external dependencies required

### Design Assets
- ✅ Use existing SF Symbols
- ✅ Use existing color semantics from `Color+Semantics.swift`
- ✅ No new assets needed

### Team Coordination
- None required (single developer)
- Consider user testing for Iteration 3 (workout mode)

---

## Open Questions

1. **Workout Mode Toggle**: Should this be:
   - Per-workout persistent state?
   - Global app setting?
   - Auto-detect based on time of day?
   
   **Recommendation**: Start without toggle, use enhanced gestures only. Add toggle later if needed.

2. **Coaching Notes Default State**: Should it remember user preference?
   
   **Recommendation**: No - keep simple, always default to collapsed. Users who want to read notes can expand.

3. **Program Context**: Show in calendar view only, workout view only, or both?
   
   **Recommendation**: Both - redundancy is okay for critical context.

4. **Exercise Navigation**: Swipe only, buttons only, or both?
   
   **Recommendation**: Both - swipe for power users, buttons for discoverability.

---

## Conclusion

This plan prioritizes **high-impact, low-complexity changes** that realign the UI with user needs while maintaining code quality. The phased approach allows for:

1. **Quick wins**: Iteration 1 & 2 deliver 60% of the value in 30% of the time
2. **Low risk**: Each iteration is independent and reversible
3. **Measurable progress**: Clear metrics for each phase
4. **Maintainable code**: Small, focused components with single responsibilities

**Estimated Total Effort**: 6-10 hours over 2-3 days
**Expected Impact**: Jobs-to-be-done score improvement from 5.35/10 to 8.2/10 (53% increase)

Next step: Review this plan, make any adjustments, then begin implementation in Code mode.