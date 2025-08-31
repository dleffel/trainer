# ProactiveCoachManager Migration Guide

## Overview
This guide walks through migrating from the monolithic `ProactiveCoachManager` to the new modular architecture with three focused components.

## Step-by-Step Migration

### Step 1: Update AppDelegate

Replace references to `ProactiveCoachManager` with `ProactiveScheduler`:

```swift
// Old
ProactiveCoachManager.shared.handleBackgroundRefresh(task)

// New
ProactiveScheduler.shared.handleBackgroundRefresh(task)
```

### Step 2: Update View Controllers

In views that trigger proactive checks:

```swift
// Old
await ProactiveCoachManager.shared.triggerEvaluation()

// New
await ProactiveScheduler.shared.triggerEvaluation()
```

### Step 3: Update Initialization

In your app startup code:

```swift
// Old
Task {
    await ProactiveCoachManager.shared.initialize()
}

// New
Task {
    await ProactiveScheduler.shared.initialize()
}
```

### Step 4: Update Settings View

The settings view should now interact with `ProactiveScheduler`:

```swift
// Old
ProactiveCoachManager.shared.recordAppOpen()

// New
ProactiveScheduler.shared.recordAppOpen()
```

## Dependency Injection Example

For better testability, you can inject dependencies:

```swift
// Create custom instances
let coachBrain = CoachBrain()
let messageDelivery = MessageDeliveryService()
let scheduler = ProactiveScheduler(
    coachBrain: coachBrain,
    messageDelivery: messageDelivery
)

// Use in tests with mocks
let mockBrain = MockCoachBrain()
let mockDelivery = MockMessageDeliveryService()
let testScheduler = ProactiveScheduler(
    coachBrain: mockBrain,
    messageDelivery: mockDelivery
)
```

## Feature Flag Implementation

To safely roll out the new architecture:

```swift
struct FeatureFlags {
    static var useRefactoredProactiveMessaging: Bool {
        UserDefaults.standard.bool(forKey: "feature.refactored_proactive")
    }
}

// In your initialization code
if FeatureFlags.useRefactoredProactiveMessaging {
    await ProactiveScheduler.shared.initialize()
} else {
    await ProactiveCoachManager.shared.initialize()
}
```

## Testing the Migration

### 1. Unit Tests
Run the new unit tests for each component:
```bash
xcodebuild test -scheme TrainerApp -only-testing:TrainerAppTests/CoachBrainTests
xcodebuild test -scheme TrainerApp -only-testing:TrainerAppTests/MessageDeliveryTests
xcodebuild test -scheme TrainerApp -only-testing:TrainerAppTests/ProactiveSchedulerTests
```

### 2. Integration Tests
Test the full flow:
```swift
func testProactiveMessagingFlow() async {
    // Initialize
    let success = await ProactiveScheduler.shared.initialize()
    XCTAssertTrue(success)
    
    // Trigger evaluation
    await ProactiveScheduler.shared.triggerEvaluation()
    
    // Verify message was sent (check notifications)
}
```

### 3. Manual Testing Checklist
- [ ] App launches without crashes
- [ ] Proactive messages are sent at expected intervals
- [ ] Quiet hours are respected
- [ ] Rate limiting works correctly
- [ ] Messages appear in conversation history
- [ ] Notifications display properly
- [ ] Background refresh continues to work

## Rollback Plan

If issues arise, you can quickly rollback:

1. Change feature flag to false
2. Revert AppDelegate changes
3. Keep new files but don't use them
4. Monitor for 24 hours before removing new code

## Benefits After Migration

1. **Easier Testing**: Each component can be tested in isolation
2. **Better Debugging**: Clear separation makes issues easier to trace
3. **Flexible Development**: Teams can work on different components simultaneously
4. **Reusability**: CoachBrain can be used in other parts of the app
5. **Performance**: Potential for optimization in each focused component

## Common Issues and Solutions

### Issue: Notifications not appearing
**Solution**: Ensure `MessageDeliveryService` is properly initialized and has permissions

### Issue: Background tasks not running
**Solution**: Check that `ProactiveScheduler` is registering tasks correctly in AppDelegate

### Issue: Tool calls not executing
**Solution**: Verify `CoachBrain` has access to `ToolProcessor.shared`

## Next Steps

After successful migration:
1. Remove old `ProactiveCoachManager` file
2. Update documentation
3. Consider further optimizations (caching, etc.)
4. Add performance monitoring