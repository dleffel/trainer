# Chat Scroll Streaming Optimization Plan

## Executive Summary

The chat scroll behavior is janky during streaming due to **excessive UI updates** - every single token arrival triggers a full SwiftUI view update and scroll recalculation. With `.defaultScrollAnchor(.bottom)` in place, the native scroll behavior is solid, but the **update frequency** is overwhelming the rendering pipeline.

## Root Cause Analysis

### 1. **Per-Token UI Updates** (Primary Issue)
**Location:** [`StreamingCoordinator.swift:110-131`](TrainerApp/TrainerApp/Services/ConversationManager/StreamingCoordinator.swift:110-131)

Every token that arrives triggers:
```swift
Task { @MainActor in
    // This runs for EVERY token (potentially 100+ times per second)
    let updated = MessageFactory.assistantStreaming(
        content: streamedContent,
        reasoning: streamedReasoning.isEmpty ? nil : streamedReasoning
    )
    self.delegate?.streamingDidUpdateMessage(at: idx, with: updated)
}
```

**Impact:**
- 🔴 **100+ UI updates per second** during fast streaming
- 🔴 Each update triggers SwiftUI diffing, layout, and `.defaultScrollAnchor` recalculation
- 🔴 Competing with keyboard animations if visible
- 🔴 CPU/GPU thrashing from rapid re-renders

### 2. **Reasoning Preview Updates** (Secondary Issue)
**Location:** [`MessageBubble.swift:240-260`](TrainerApp/TrainerApp/Views/Chat/MessageBubble.swift:240-260)

```swift
// Only updates if we've accumulated at least 50 more characters
guard fullReasoning.count >= lastReasoningLength + 50 else { return }
```

**Status:** ✅ Already throttled (50 char batching)
**Impact:** Minor - this is reasonably optimized

### 3. **Nested ScrollView in Reasoning Preview** (Tertiary Issue)
**Location:** [`MessageBubble.swift:88-109`](TrainerApp/TrainerApp/Views/Chat/MessageBubble.swift:88-109)

```swift
ScrollViewReader { proxy in
    ScrollView {
        // Reasoning preview with auto-scroll
    }
    .onChange(of: previewLines.count) { _, _ in
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastIndex, anchor: .bottom)
        }
    }
}
```

**Impact:** 
- 🟡 Nested `ScrollView` competes with parent scroll
- 🟡 Animated scroll in preview conflicts with parent `.defaultScrollAnchor`
- 🟡 Creates layout thrashing when both are active

## Proposed Solutions

### Solution 1: Batch Streaming Updates (Primary Fix)
**Impact:** 🟢 High - Reduces updates by 90%+
**Risk:** 🟢 Low - Standard optimization pattern

Implement time-based batching in `StreamingCoordinator`:

```swift
class StreamingCoordinator {
    // MARK: - Batching Configuration
    private static let updateInterval: TimeInterval = 0.05  // 50ms = 20 FPS
    
    // MARK: - State
    private var pendingUpdate: (index: Int, message: ChatMessage)?
    private var updateTimer: Timer?
    
    // MARK: - Batched Update System
    
    private func scheduleMessageUpdate(at index: Int, with message: ChatMessage) {
        // Store the pending update
        pendingUpdate = (index, message)
        
        // Create timer if not exists
        if updateTimer == nil {
            updateTimer = Timer.scheduledTimer(
                withTimeInterval: Self.updateInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flushPendingUpdate()
            }
        }
    }
    
    private func flushPendingUpdate() {
        guard let update = pendingUpdate else { return }
        
        // Send batched update to delegate
        delegate?.streamingDidUpdateMessage(at: update.index, with: update.message)
        
        // Clear pending
        pendingUpdate = nil
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Flush any final pending update
        flushPendingUpdate()
    }
}
```

**Integration Points:**
1. Replace immediate updates in `onToken` handler (lines 110-131)
2. Replace immediate updates in `onReasoning` handler (lines 144-168)
3. Call `stopUpdateTimer()` when streaming completes (line 184)

**Benefits:**
- ✅ Reduces UI updates from ~100/sec to ~20/sec (80% reduction)
- ✅ Maintains smooth visual appearance (20 FPS is imperceptible)
- ✅ Reduces CPU/GPU load dramatically
- ✅ Coordinates better with keyboard animations
- ✅ `.defaultScrollAnchor` has time to settle between updates

### Solution 2: Optimize Reasoning Preview (Secondary Fix)
**Impact:** 🟡 Medium - Reduces nested scroll conflicts
**Risk:** 🟢 Low - Simplification

Replace animated `ScrollViewReader` with simpler approach:

```swift
// BEFORE: Nested ScrollView with animations
ScrollViewReader { proxy in
    ScrollView {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                Text(line).id(index)
            }
        }
    }
    .onChange(of: previewLines.count) { _, _ in
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(lastIndex, anchor: .bottom)
        }
    }
}

// AFTER: Simple VStack with natural bottom alignment
VStack(alignment: .leading, spacing: 2) {
    ForEach(previewLines, id: \.self) { line in
        Text(line)
            .font(.caption)
            .foregroundColor(.secondary.opacity(0.8))
            .italic()
    }
}
.frame(height: 60, alignment: .bottom)  // Natural bottom alignment
```

**Benefits:**
- ✅ Eliminates nested scroll competition
- ✅ Removes competing animations
- ✅ Simpler code, easier to maintain
- ✅ Natural bottom alignment without manual scrolling

### Solution 3: Use ScrollPosition for Fine Control (Future Enhancement)
**Impact:** 🟡 Medium - Better control over scroll behavior
**Risk:** 🟡 Medium - More complex, iOS 17+ only

Add explicit scroll position tracking:

```swift
struct MessageListView: View {
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var userHasScrolledUp = false
    
    var body: some View {
        ScrollView {
            // ... content
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .onChange(of: scrollPosition.edge) { _, newEdge in
            // Detect when user scrolls away from bottom
            userHasScrolledUp = (newEdge != .bottom)
        }
        .onChange(of: messages.count) { _, _ in
            // Only auto-scroll if user hasn't scrolled up
            if !userHasScrolledUp {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }
}
```

**Benefits:**
- ✅ Precise control over when to scroll
- ✅ Better user scroll detection
- ✅ Can disable auto-scroll when user is reading history

**Note:** This is optional - `.defaultScrollAnchor` already handles most of this automatically.

## Implementation Priority

### Phase 1: Batch Streaming Updates (CRITICAL)
**Files to Modify:**
1. [`StreamingCoordinator.swift`](TrainerApp/TrainerApp/Services/ConversationManager/StreamingCoordinator.swift)
   - Add batching timer system (lines 24-44)
   - Replace immediate updates with `scheduleMessageUpdate()` (lines 110-131, 144-168)
   - Add cleanup in completion (line 184)

**Expected Improvement:** 80-90% reduction in jankiness

### Phase 2: Simplify Reasoning Preview (RECOMMENDED)
**Files to Modify:**
1. [`MessageBubble.swift`](TrainerApp/TrainerApp/Views/Chat/MessageBubble.swift)
   - Replace `ScrollViewReader` with simple `VStack` (lines 88-109)
   - Remove `onChange` scroll animation

**Expected Improvement:** 10-20% additional smoothness

### Phase 3: ScrollPosition Enhancement (OPTIONAL)
**Files to Modify:**
1. [`MessageListView.swift`](TrainerApp/TrainerApp/Views/Chat/MessageListView.swift)
   - Add `@State private var scrollPosition`
   - Bind with `.scrollPosition($scrollPosition)`
   - Add user scroll detection

**Expected Improvement:** Better control, not necessarily smoother

## Performance Metrics

### Current State (Estimated)
- **UI Updates/Second:** ~100-150 during fast streaming
- **Frame Drops:** Frequent (janky)
- **CPU Usage:** High during streaming
- **Scroll Smoothness:** Poor

### After Phase 1 (Batching)
- **UI Updates/Second:** ~20 (50ms batching)
- **Frame Drops:** Rare
- **CPU Usage:** Normal
- **Scroll Smoothness:** Smooth

### After Phase 2 (Preview Optimization)
- **UI Updates/Second:** ~20
- **Frame Drops:** Very rare
- **CPU Usage:** Low
- **Scroll Smoothness:** Very smooth

## Testing Checklist

After implementing batching:

### Streaming Behavior
- [ ] Content appears smoothly during streaming (no visible delay)
- [ ] No dropped tokens or missing content
- [ ] Final message content is complete and accurate
- [ ] Scroll stays at bottom during streaming

### Reasoning Behavior
- [ ] Reasoning preview updates smoothly
- [ ] No conflicts between reasoning and content updates
- [ ] Reasoning is complete when streaming finishes

### Keyboard Interaction
- [ ] Smooth scrolling when keyboard appears during streaming
- [ ] No jumps or jank when keyboard dismisses
- [ ] Content remains visible above keyboard

### User Control
- [ ] User can scroll up during streaming
- [ ] Auto-scroll disengages when user scrolls up
- [ ] Auto-scroll re-engages when user scrolls to bottom

## Alternative Approaches Considered

### ❌ Debouncing Instead of Batching
**Why Not:** Debouncing delays all updates until silence, creating lag at the start and end of streaming.

### ❌ Removing `.defaultScrollAnchor`
**Why Not:** This is the correct native API - the problem is update frequency, not the scroll mechanism.

### ❌ Manual ScrollViewReader Management
**Why Not:** We already tried this (see `ChatScrollNativeBehaviorPlan.md`) - native APIs are better.

### ❌ Throttling at Network Layer
**Why Not:** Doesn't solve the problem - tokens still arrive rapidly, just in bursts.

## References

- [Apple: Optimizing SwiftUI Performance](https://developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui)
- [WWDC 2023: Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/)
- Previous work: [`ChatScrollNativeBehaviorPlan.md`](ChatScrollNativeBehaviorPlan.md)
- Previous work: [`MessageListPerformanceOptimizationPlan.md`](MessageListPerformanceOptimizationPlan.md)

## Success Criteria

✅ **Smooth scrolling during streaming** - No visible jank or stuttering
✅ **Responsive to user interaction** - User can scroll up/down without lag
✅ **Keyboard coordination** - Smooth transitions when keyboard appears/dismisses
✅ **No dropped content** - All tokens appear in final message
✅ **Lower CPU usage** - Reduced battery drain during streaming