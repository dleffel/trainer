# Plan to Remove All Proactive Messaging Features

## Overview
This plan details the complete removal of proactive messaging functionality from the TrainerApp, including all background tasks, notifications, scheduled checks, and LLM-driven proactive coaching features.

## Components to Remove

### 1. Core Manager Classes (Delete Entirely)
- **ProactiveCoachManager.swift** - 853+ line legacy manager
- **ProactiveScheduler.swift** - Refactored scheduler component  
- **MessageDeliveryService.swift** - Notification delivery service
- **ProactiveMessagingTypes.swift** - Shared types and structs

### 2. UI Components (Delete Entirely)
- **ProactiveMessagingSettingsView.swift** - Settings interface for proactive features

### 3. Integration Points to Clean Up

#### TrainerAppApp.swift
- Remove AppDelegate class entirely
- Remove @UIApplicationDelegateAdaptor
- Remove ProactiveCoachManager.shared.recordAppOpen() call
- Remove background task registration code
- Keep deep linking for calendar navigation (non-proactive feature)

#### ContentView.swift
- No changes needed (only imports persistence which is used for regular chat)

#### CoachBrain.swift
- Remove proactive-specific methods if any exist
- Keep tool processing capabilities for regular chat

#### Info.plist
- Remove BGTaskSchedulerPermittedIdentifiers entry
- Remove UIBackgroundModes entries for:
  - background-processing
  - fetch
  - processing  
  - remote-notification
- Keep NSUserNotificationsUsageDescription (may be used for other features)

### 4. UserDefaults Keys to Clean
- proactiveMessagingEnabled
- proactiveCheckInterval
- proactiveMaxMessagesPerDay
- proactiveQuietHoursEnabled
- proactiveQuietHoursStart
- proactiveQuietHoursEnd
- proactiveSundayReviewEnabled
- proactiveSundayReviewHour

### 5. Documentation Files to Delete
All proactive messaging related documentation:
- Proactive_Messaging_Architecture.md
- Proactive_Messaging_Implementation_Summary.md
- Proactive_Messaging_Flow.md
- Proactive_Messaging_Troubleshooting.md
- Proactive_Messaging_Bugs_Fixed.md
- Proactive_Messaging_Bug_Fix.md
- ProactiveCoachManager_Migration_Guide.md
- ProactiveCoachManager_Refactoring_Plan.md
- Enhanced_Proactive_Messaging_Architecture.md
- Enhanced_Proactive_Messaging_Implementation.md
- LLM_Driven_Proactive_Messaging.md
- Intelligent_Onboarding_Summary.md (if primarily about proactive messaging)
- Typing_Indicator_Implementation_Plan.md (if for proactive messaging)

### 6. Xcode Project File Updates
Remove references to deleted files from project.pbxproj:
- ProactiveCoachManager.swift
- ProactiveScheduler.swift
- MessageDeliveryService.swift
- ProactiveMessagingTypes.swift
- ProactiveMessagingSettingsView.swift

## Implementation Steps

### Step 1: Delete Core Files
```bash
rm TrainerApp/TrainerApp/Managers/ProactiveCoachManager.swift
rm TrainerApp/TrainerApp/Managers/ProactiveScheduler.swift
rm TrainerApp/TrainerApp/Services/MessageDeliveryService.swift
rm TrainerApp/TrainerApp/Models/ProactiveMessagingTypes.swift
rm TrainerApp/TrainerApp/Views/ProactiveMessagingSettingsView.swift
```

### Step 2: Clean TrainerAppApp.swift
- Remove AppDelegate class
- Remove background task registration
- Remove proactive messaging initialization
- Keep NavigationState and deep linking

### Step 3: Update Info.plist
- Remove background task identifiers
- Remove unnecessary background modes
- Keep essential permissions

### Step 4: Update Xcode Project
- Remove file references from project.pbxproj
- Clean build folder
- Test compilation

### Step 5: Delete Documentation
```bash
rm TrainerApp/*Proactive*.md
rm TrainerApp/LLM_Driven_Proactive_Messaging.md
rm TrainerApp/Intelligent_Onboarding_Summary.md
rm TrainerApp/Enhanced_Proactive_Messaging_*.md
```

### Step 6: Test App
- Verify app compiles without errors
- Test regular chat functionality still works
- Verify calendar deep links still function
- Confirm no background tasks are running

## Features That Will Remain

### Preserved Functionality:
- Regular chat-based coaching
- Manual workout tracking
- Calendar view and navigation
- Deep linking to calendar dates
- HealthKit integration
- Tool processing for chat
- Settings for API key
- Debug menu
- API logging

### What Users Will Lose:
- Automatic workout reminders
- Smart check-ins based on patterns
- Sunday weekly reviews
- Proactive program initialization
- Background coaching evaluations
- All automated notifications from the coach

## Validation Checklist

- [ ] All proactive messaging files deleted
- [ ] TrainerAppApp.swift cleaned of proactive code
- [ ] Info.plist background modes removed
- [ ] Xcode project builds without errors
- [ ] No references to ProactiveCoachManager remain
- [ ] No references to ProactiveScheduler remain
- [ ] No references to MessageDeliveryService remain
- [ ] Regular chat functionality works
- [ ] Calendar functionality works
- [ ] Documentation files removed

## Notes

- The ConversationPersistence class should remain as it's used for regular chat
- Keep ToolProcessor as it's used for regular chat interactions
- The SystemPrompt.md may need review to remove any proactive messaging instructions
- Consider whether to keep notification permissions for potential future features