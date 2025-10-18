# Scroll-to-Dismiss Keyboard Implementation Plan

## Overview
Add native iOS scroll-to-dismiss keyboard behavior to the chat message list with a single modifier.

## Change Required

### File: MessageListView.swift
**Location:** Line 38 (after the ScrollView closing brace)

**Current Code (lines 16-38):**
```swift
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(messages) { msg in
            bubble(for: msg)
                .id(msg.id)
        }
        
        // Use the unified status view from ChatStateComponents
        if chatState != .idle {
            ChatStatusView(state: chatState)
                .id("status-indicator")
                .padding(.horizontal, 4)
        }
        
        // Add invisible spacer at bottom to ensure last message isn't cut off
        Color.clear
            .frame(height: 20)
            .id("bottom-spacer")
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 8)
}
```

**Modified Code:**
```swift
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(messages) { msg in
            bubble(for: msg)
                .id(msg.id)
        }
        
        // Use the unified status view from ChatStateComponents
        if chatState != .idle {
            ChatStatusView(state: chatState)
                .id("status-indicator")
                .padding(.horizontal, 4)
        }
        
        // Add invisible spacer at bottom to ensure last message isn't cut off
        Color.clear
            .frame(height: 20)
            .id("bottom-spacer")
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 8)
}
.scrollDismissesKeyboard(.interactively)  // ADD THIS LINE
```

## Implementation Details

### Modifier: `.scrollDismissesKeyboard(.interactively)`
- **Platform:** iOS 16.0+ (app already targets iOS 17.0+)
- **Behavior:** Keyboard dismisses as user scrolls, following scroll gestures
- **Mode:** `.interactively` = Keyboard tracks scroll position (most natural)
- **Alternative:** `.immediately` would dismiss keyboard as soon as scroll starts

### Why This Works
1. User scrolls up to read previous messages → keyboard smoothly slides down
2. User scrolls down → keyboard stays dismissed
3. Tapping the TextField brings keyboard back when needed
4. Zero additional UI elements or complexity

## Testing Checklist

After implementation, verify:
- [ ] Keyboard dismisses when scrolling up through messages
- [ ] Keyboard dismisses when scrolling down
- [ ] Keyboard can be brought back by tapping TextField
- [ ] Scroll position is maintained correctly
- [ ] Auto-scroll to bottom still works when new messages arrive
- [ ] Send button remains functional during scroll
- [ ] Photo attachment button still accessible

## Edge Cases Covered

✅ **New message arrives while scrolling:** Auto-scroll logic (lines 39-47) still works
✅ **User taps send while keyboard is dismissed:** Message sends normally
✅ **Keyboard is up, user receives message:** Auto-scroll brings keyboard into view naturally
✅ **Multi-line text input:** Keyboard dismissal doesn't interfere with text entry

## Performance Impact

**Minimal:** Single SwiftUI modifier, no state management overhead.

## Rollback Plan

If issues arise, simply remove the `.scrollDismissesKeyboard(.interactively)` line to restore original behavior.

## Future Enhancements

Once this minimal change is validated, consider:
- Tab-switch keyboard dismissal (ContentView)
- Tap-to-dismiss on message list background
- Keyboard toolbar with "Done" button

These can be added incrementally based on user feedback.