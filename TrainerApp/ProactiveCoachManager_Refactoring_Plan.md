# ProactiveCoachManager Refactoring Plan

## Overview
This plan details the refactoring of the monolithic ProactiveCoachManager (802 lines) into three focused, testable components:

1. **CoachBrain** - Pure decision-making logic
2. **ProactiveScheduler** - Timing and rate limiting
3. **MessageDeliveryService** - Notification handling

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Current Architecture                     │
│                                                              │
│  ProactiveCoachManager (802 lines)                         │
│  - LLM decisions                                            │
│  - Tool processing                                          │
│  - Background tasks                                         │
│  - Notifications                                            │
│  - Persistence                                              │
│  - State tracking                                           │
│  - Context gathering                                        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      New Architecture                        │
│                                                              │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │   CoachBrain    │  │ProactiveScheduler│  │  Message   │ │
│  │                 │  │                  │  │  Delivery  │ │
│  │ • LLM logic     │  │ • Timing logic   │  │ • Notify   │ │
│  │ • Tool calls    │  │ • Rate limiting  │  │ • Persist  │ │
│  │ • Decisions     │  │ • Background     │  │ • Format   │ │
│  └─────────────────┘  └──────────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. CoachBrain (Stateless Decision Engine)
**Responsibility**: Pure LLM decision-making and tool processing
**Lines of Code**: ~250 lines
**Dependencies**: ToolProcessor, LLMClient, SystemPromptLoader

### 2. ProactiveScheduler (Background Orchestrator)
**Responsibility**: When to check, rate limiting, suppression rules
**Lines of Code**: ~200 lines
**Dependencies**: CoachBrain, MessageDeliveryService, BackgroundTasks

### 3. MessageDeliveryService (Delivery Layer)
**Responsibility**: Notifications, persistence, formatting
**Lines of Code**: ~150 lines
**Dependencies**: ConversationPersistence, UNUserNotificationCenter

## Migration Steps

### Phase 1: Extract CoachBrain (Week 1)
1. Create new `CoachBrain.swift` file
2. Move decision-making logic
3. Create protocol for testability
4. Write unit tests

### Phase 2: Extract MessageDeliveryService (Week 1)
1. Create new `MessageDeliveryService.swift`
2. Move notification logic
3. Move persistence logic
4. Create tests

### Phase 3: Refactor ProactiveScheduler (Week 2)
1. Rename existing manager
2. Remove extracted logic
3. Wire up dependencies
4. Integration tests

### Phase 4: Clean Up (Week 2)
1. Remove duplicated code
2. Update documentation
3. Performance testing

## Key Benefits

1. **Testability**: Mock dependencies easily
2. **Reusability**: Use CoachBrain in chat view
3. **Maintainability**: Clear separation of concerns
4. **Extensibility**: Easy to add new delivery channels

## Risk Mitigation

- Keep old manager during transition
- Feature flag for gradual rollout
- Comprehensive test coverage before switching
- Monitor crash rates and user feedback