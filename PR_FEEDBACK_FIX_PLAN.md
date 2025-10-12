# PR Feedback Fix Plan

## Issues to Address

### 1. Remove Leftover Modal Sheet in Bubble View ✅
**Location**: `ContentView.swift` lines 402, 492-495, 545-569

**Problem**: 
- Bubble view still has local `@State private var showCalendar` 
- Still presents CalendarView via `.sheet(isPresented: $showCalendar)`
- `handleURL()` sets `showCalendar = true` instead of using navigationState

**Fix**:
- Remove `@State private var showCalendar = false` (line 402)
- Remove `.sheet(isPresented: $showCalendar) { CalendarView()... }` (lines 492-495)
- Update `handleURL()` to set `navigationState.selectedTab = 1` instead of `showCalendar = true` (line 559)
- Deep link flow: Bubble.handleURL() → navigationState.targetWorkoutDate + selectedTab → Log tab shows → WeeklyCalendarView.handleDeepLinkNavigation() → navigates to workout

### 2. Clean Up NavigationState.showCalendar ✅
**Location**: `TrainerAppApp.swift` line 12

**Problem**:
- `showCalendar` flag is still set in `navigateToWorkoutDay()`
- No longer used since modal was removed
- Creates confusion

**Fix**:
- Remove `@Published var showCalendar = false` from NavigationState
- Remove `showCalendar = true` from `navigateToWorkoutDay()` 
- Remove `.onChange(of: navigationState.showCalendar)` from ContentView (lines 116-121)

### 3. Restore Error Handling in ChatTab ✅
**Location**: `ContentView.swift` lines 322-327

**Problem**:
- Error handling was changed from user-facing alert to silent print
- Users won't see when message sending fails

**Fix**:
- Add `@State private var errorMessage: String?` to ChatTab
- Restore error alert in ChatTab body
- Set `errorMessage` in catch block instead of just printing

### 4. Verify Deep Link Handling ✅
**Status**: Already working correctly!

**Verified**:
- WeeklyCalendarView observes `navigationState.targetWorkoutDate` (line 86-88)
- `handleDeepLinkNavigation()` properly navigates to workout (lines 258-278)
  - Sets selectedWeek to targetDate
  - Loads the week
  - Selects the specific workout day
  - Clears targetWorkoutDate when done
- CalendarContentView doesn't need changes - just passes through to WeeklyCalendarView

## Implementation Steps

### Step 1: Fix Bubble View
```swift
// Remove line 402
// @State private var showCalendar = false

// Remove lines 492-495
// .sheet(isPresented: $showCalendar) {
//     CalendarView()
//         .environmentObject(navigationState)
// }

// Update handleURL() around line 558
if let date = dateFormatter.date(from: dateString) {
    print("✅ Parsed deep link date: \(date)")
    navigationState.targetWorkoutDate = date
    navigationState.selectedTab = 1  // Switch to Log tab
}
```

### Step 2: Clean NavigationState
```swift
// TrainerAppApp.swift
class NavigationState: ObservableObject {
    @Published var selectedTab = 0
    @Published var targetWorkoutDate: Date?
    // Remove: @Published var showCalendar = false
    
    func navigateToWorkoutDay(date: Date) {
        targetWorkoutDate = date
        selectedTab = 1
        // Remove: showCalendar = true
    }
}
```

```swift
// ContentView.swift - Remove lines 116-121
// .onChange(of: navigationState.showCalendar) { _, newValue in
//     if newValue {
//         navigationState.selectedTab = 1
//         navigationState.showCalendar = false
//     }
// }
```

### Step 3: Restore Error Handling
```swift
// Add to ChatTab
private struct ChatTab: View {
    @ObservedObject var conversationManager: ConversationManager
    @Binding var showSettings: Bool
    let iCloudAvailable: Bool
    
    @EnvironmentObject var navigationState: NavigationState
    @State private var input: String = ""
    @State private var errorMessage: String?  // Add this
    
    // ... rest of code ...
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesList
                inputBar
            }
            // ... toolbar ...
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }
    
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        input = ""
        
        do {
            try await conversationManager.sendMessage(text)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
```

## Testing Checklist

After implementing fixes:

1. ✅ Verify clicking workout link in chat switches to Log tab
2. ✅ Verify Log tab navigates to correct workout date
3. ✅ Verify no modal calendar appears anywhere
4. ✅ Verify errors are shown to user when message sending fails
5. ✅ Build succeeds without warnings
6. ✅ Deep links from external sources still work

## Files to Modify

1. `TrainerApp/TrainerApp/ContentView.swift`
   - Remove Bubble.showCalendar state and sheet
   - Update Bubble.handleURL()
   - Add ChatTab.errorMessage and alert
   - Update ChatTab.send() error handling
   - Remove onChange for navigationState.showCalendar

2. `TrainerApp/TrainerApp/TrainerAppApp.swift`
   - Remove NavigationState.showCalendar
   - Update navigateToWorkoutDay()