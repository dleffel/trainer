# ContentView Refactoring Plan

## Current State Analysis

ContentView.swift is 997 lines and contains multiple responsibilities:
- Main app container with tab navigation
- Complete chat interface (messages, input, bubbles)
- Calendar tab wrapper
- Settings sheet with all configuration options
- Photo attachment handling
- Link detection and deep linking
- iCloud synchronization setup

## Problems

1. **Single Responsibility Violation**: One file handles navigation, chat UI, settings, photo picking, and more
2. **Maintainability**: Nearly 1000 lines makes it difficult to navigate and modify
3. **Testability**: Components are tightly coupled and difficult to test in isolation
4. **Reusability**: Useful components like `LinkDetectingText` and `PhotoAttachmentButton` are buried as private structs
5. **Code Organization**: No clear separation between app-level concerns and feature-specific UI

## Refactoring Strategy

Extract components into a logical directory structure following the existing pattern established by [`ChatStateComponents.swift`](TrainerApp/TrainerApp/Views/ChatStateComponents.swift:1).

### New File Structure

```
TrainerApp/TrainerApp/Views/
├── ContentView.swift (simplified, ~150 lines)
├── ChatStateComponents.swift (existing)
├── WeeklyCalendarView.swift (existing)
├── Chat/
│   ├── ChatView.swift
│   ├── MessageBubble.swift
│   ├── ChatInputBar.swift
│   └── MessageListView.swift
├── Calendar/
│   └── CalendarTabView.swift
├── Settings/
│   └── SettingsView.swift
└── Shared/
    ├── LinkDetectingText.swift
    ├── PhotoAttachmentButton.swift
    └── ImagePicker.swift
```

## Detailed Migration Plan

### Phase 1: Extract Shared/Utility Components

These components are reusable and have no dependencies on app-specific state.

#### 1.1 Create `Views/Shared/LinkDetectingText.swift`
- **Lines to extract**: 664-755
- **Dependencies**: None (SwiftUI only)
- **Public interface**: `LinkDetectingText(text:isUser:onTap:)`
- **Purpose**: Detects and makes trainer:// links tappable in text

#### 1.2 Create `Views/Shared/ImagePicker.swift`
- **Lines to extract**: 949-988
- **Dependencies**: UIKit
- **Public interface**: `ImagePicker(sourceType:onImageSelected:)`
- **Purpose**: UIKit camera wrapper

#### 1.3 Create `Views/Shared/PhotoAttachmentButton.swift`
- **Lines to extract**: 887-945
- **Dependencies**: PhotosUI, ImagePicker
- **Public interface**: `PhotoAttachmentButton(selectedImages:)`
- **Purpose**: Photo selection menu (camera + library)

### Phase 2: Extract Chat Components

These components handle the chat interface and are cohesive units.

#### 2.1 Create `Views/Chat/MessageBubble.swift`
- **Lines to extract**: 449-661
- **Dependencies**: 
  - ConversationManager (ObservedObject)
  - NavigationState (EnvironmentObject)
  - LinkDetectingText
- **Public interface**: `MessageBubble(messageId:text:reasoning:isUser:isLastMessage:conversationManager:attachments:)`
- **Features**:
  - Reasoning display with streaming preview
  - Image attachments
  - Deep link handling
  - Equatable conformance for performance
- **Notes**: Keep `updatePreviewLines()` and `handleURL()` as private methods

#### 2.2 Create `Views/Chat/ChatInputBar.swift`
- **Lines to extract**: 313-366 (inputBar property)
- **Dependencies**:
  - PhotoAttachmentButton
  - ChatState
- **Public interface**: `ChatInputBar(input:selectedImages:chatState:canSend:onSend:)`
- **Features**:
  - Text input with multi-line support
  - Photo preview thumbnails
  - Send button state
- **Notes**: Accept closures for actions to maintain separation

#### 2.3 Create `Views/Chat/MessageListView.swift`
- **Lines to extract**: 204-271 (messagesList + scrollToBottom)
- **Dependencies**:
  - ChatMessage array
  - ChatState
  - MessageBubble
  - ChatStatusView
- **Public interface**: `MessageListView(messages:chatState:conversationManager:)`
- **Features**:
  - ScrollView with auto-scroll
  - Message rendering
  - Status indicator display
- **Notes**: Keep scroll logic internal

#### 2.4 Create `Views/Chat/ChatView.swift`
- **Lines to extract**: 145-395 (ChatTab)
- **Dependencies**:
  - ConversationManager
  - NavigationState
  - MessageListView
  - ChatInputBar
- **Public interface**: `ChatView(conversationManager:showSettings:iCloudAvailable:)`
- **Purpose**: Assemble chat components into complete interface
- **Features**:
  - Navigation stack
  - Toolbar with iCloud indicator
  - Error alert handling

### Phase 3: Extract Settings Component

#### 3.1 Create `Views/Settings/SettingsView.swift`
- **Lines to extract**: 757-883
- **Dependencies**:
  - AppConfiguration
  - TrainingScheduleManager
  - DebugMenuView
  - SimpleDeveloperTimeControl
- **Public interface**: `SettingsView(onClearChat:)`
- **Features**:
  - API key configuration
  - Developer options
  - AI reasoning toggle
  - Data clearing functions
- **Notes**: Keep all UserDefaults and settings logic contained

### Phase 4: Extract Calendar Component

#### 4.1 Create `Views/Calendar/CalendarTabView.swift`
- **Lines to extract**: 399-445 (LogTab + CalendarContentView)
- **Dependencies**:
  - TrainingScheduleManager
  - NavigationState
  - WeeklyCalendarView
- **Public interface**: `CalendarTabView(showSettings:)`
- **Features**:
  - Navigation stack
  - Deep link handling for workout navigation
  - WeeklyCalendarView integration
- **Notes**: Merge LogTab and CalendarContentView into single cohesive view

### Phase 5: Simplify ContentView

#### 5.1 Refactor `ContentView.swift`
- **Keep**: ~150 lines
- **Responsibilities** (only):
  - TabView setup
  - Top-level state (@StateObject, @State)
  - iCloud availability checking
  - Notification observers (iCloud, proactive messages)
  - HealthKit authorization
  - API key migration
  - Settings sheet presentation
  - Error alerts
- **Use new components**:
  - ChatView for tab 0
  - CalendarTabView for tab 1
  - SettingsView in sheet

## Implementation Order

1. **Shared components first** (no dependencies on other new files)
   - LinkDetectingText
   - ImagePicker
   - PhotoAttachmentButton

2. **Chat components** (depend on shared components)
   - MessageBubble (uses LinkDetectingText)
   - ChatInputBar (uses PhotoAttachmentButton)
   - MessageListView (uses MessageBubble)
   - ChatView (assembles all chat components)

3. **Settings view** (independent)
   - SettingsView

4. **Calendar view** (independent)
   - CalendarTabView

5. **ContentView update** (uses all new components)
   - Replace inline components with imports
   - Simplify to ~150 lines

## Key Principles

1. **Maintain Existing Architecture**: Don't change how ConversationManager, NavigationState, or other managers work
2. **Preserve Functionality**: All features must work exactly as before
3. **Public vs Private**: Only expose what needs to be reusable; keep implementation details private
4. **Dependencies**: Each file should have clear, minimal dependencies
5. **Performance**: Maintain existing optimizations (Equatable conformance, scroll optimization, etc.)
6. **SwiftUI Patterns**: Use @ObservedObject, @EnvironmentObject, and @Binding appropriately

## Testing Strategy

After each phase:
1. Build project to ensure no compilation errors
2. Run app and verify functionality
3. Test affected features:
   - Phase 1: Photo attachment, link tapping
   - Phase 2: Full chat flow, scrolling, reasoning display
   - Phase 3: Settings changes, data clearing
   - Phase 4: Calendar navigation, deep linking
   - Phase 5: Tab navigation, iCloud sync, all features

## Benefits

1. **Maintainability**: Each file has a single, clear purpose
2. **Testability**: Components can be tested in isolation
3. **Reusability**: Shared components can be used elsewhere
4. **Readability**: ~150 line files are much easier to understand
5. **Collaboration**: Multiple developers can work on different views simultaneously
6. **Debugging**: Issues are easier to locate in smaller, focused files

## File Size Targets

- ContentView.swift: 150 lines (from 997)
- Each chat component: 100-200 lines
- Settings: 150 lines
- Calendar: 100 lines
- Shared components: 50-100 lines each

## Migration Checklist

- [ ] Create Views/Shared/ directory
- [ ] Extract LinkDetectingText
- [ ] Extract ImagePicker
- [ ] Extract PhotoAttachmentButton
- [ ] Create Views/Chat/ directory
- [ ] Extract MessageBubble
- [ ] Extract ChatInputBar
- [ ] Extract MessageListView
- [ ] Extract ChatView
- [ ] Create Views/Settings/ directory
- [ ] Extract SettingsView
- [ ] Create Views/Calendar/ directory
- [ ] Extract CalendarTabView
- [ ] Simplify ContentView to use new components
- [ ] Test all functionality
- [ ] Update project.pbxproj if needed
- [ ] Verify build and run

## Notes

- All new files should include proper MARK comments
- Maintain existing accessibility labels
- Preserve all performance optimizations
- Keep existing error handling patterns
- Don't change any business logic or manager interactions