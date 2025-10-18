# Message Sending Resiliency Enhancement Plan

## Overview
Enhance the TrainerApp's message sending system to be resilient to failures with clear status tracking and easy retry capabilities.

## Current Architecture Analysis

### Message Flow
1. **User sends message** → [`ConversationManager.sendMessage()`](TrainerApp/TrainerApp/Services/ConversationManager.swift:68)
2. **Message persisted** → Immediately via [`ConversationPersistence`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift:92)
3. **API call** → Via [`LLMService`](TrainerApp/TrainerApp/Services/LLMService.swift:41) (streaming/non-streaming)
4. **Response handling** → Via [`ResponseOrchestrator`](TrainerApp/TrainerApp/Services/ConversationManager/ResponseOrchestrator.swift:31)
5. **Final persistence** → After successful completion

### Current Limitations
- ❌ No retry mechanism for failed API calls
- ❌ No persistent tracking of send status
- ❌ Network failures immediately throw errors
- ❌ No exponential backoff for transient failures
- ❌ No offline queue
- ❌ Error state not persisted across app restarts
- ❌ No manual retry UI

## Proposed Architecture

### 1. Enhanced Message States

**Extend [`MessageState`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift:7) enum:**

```swift
enum MessageState: String, Codable {
    // Existing
    case completed
    case streaming
    case processing
    
    // NEW: Send status tracking
    case pending        // Queued, not yet sent
    case sending        // Currently being sent
    case retrying(Int)  // Retrying (with attempt count)
    case failed(Error)  // Failed with specific error
    case offline        // Waiting for network
}
```

**Alternative (cleaner separation):**

```swift
// Keep MessageState simple for message processing
enum MessageState: String, Codable {
    case completed, streaming, processing
}

// NEW: Separate SendStatus for network/retry state
enum SendStatus: Codable {
    case notSent        // User message pending send
    case sending        // API call in progress
    case sent           // Successfully sent
    case retrying(attempt: Int, maxAttempts: Int)
    case failed(reason: FailureReason, canRetry: Bool)
    case offline        // No network, will retry when online
    
    enum FailureReason: String, Codable {
        case networkError
        case serverError
        case authenticationError
        case rateLimitError
        case timeout
        case unknown
    }
}
```

### 2. Message Retry Manager

**New component: `MessageRetryManager`**

**Location:** `TrainerApp/TrainerApp/Services/MessageRetryManager.swift`

**Responsibilities:**
- Track send status for each message
- Implement exponential backoff retry strategy
- Queue messages when offline
- Provide retry API for manual retries
- Persist retry state

**Key Features:**

```swift
@MainActor
class MessageRetryManager {
    // MARK: - Configuration
    struct RetryConfiguration {
        let maxAttempts: Int = 3
        let baseDelay: TimeInterval = 1.0  // 1 second
        let maxDelay: TimeInterval = 30.0  // 30 seconds
        let backoffMultiplier: Double = 2.0
        let retryableErrors: Set<FailureReason> = [.networkError, .timeout, .serverError]
    }
    
    // MARK: - State Tracking
    private var sendStatus: [UUID: SendStatus] = [:]  // messageId -> status
    private var retryQueue: [UUID] = []  // Messages waiting to retry
    
    // MARK: - Public Interface
    func sendMessage(_ message: ChatMessage, 
                     attempt: Int = 1) async throws -> SendResult
    
    func retryMessage(_ messageId: UUID) async throws
    
    func cancelRetry(_ messageId: UUID)
    
    func getSendStatus(_ messageId: UUID) -> SendStatus
    
    func processOfflineQueue() async  // When network returns
}
```

### 3. Network Monitoring

**New component: `NetworkMonitor`**

**Location:** `TrainerApp/TrainerApp/Services/NetworkMonitor.swift`

**Uses:** Apple's `Network` framework for reachability

```swift
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    
    func startMonitoring()
    func stopMonitoring()
}
```

### 4. Enhanced Persistence

**Update [`ChatMessage`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift:33):**

```swift
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let reasoning: String?
    let date: Date
    var state: MessageState
    let attachments: [MessageAttachment]?
    
    // NEW: Send tracking
    var sendStatus: SendStatus?  // Only for user messages
    var lastRetryAttempt: Date?
    var retryCount: Int = 0
}
```

**Use Tier 2 (HybridCloudStore) for retry state:**
- Store in `PersistenceKey.MessageRetry.status_{messageId}`
- Sync across devices
- Clear on successful send

### 5. Enhanced LLMService Error Handling

**Update [`LLMService`](TrainerApp/TrainerApp/Services/LLMService.swift:41):**

```swift
// Enhanced error with retry info
enum LLMError: LocalizedError {
    case missingContent
    case invalidResponse
    case httpError(Int, isRetryable: Bool)
    case networkError(Error, isRetryable: Bool)
    case timeout
    
    var isRetryable: Bool {
        switch self {
        case .httpError(let code, let retry):
            return retry || (500...599).contains(code)  // Server errors
        case .networkError(_, let retry):
            return retry
        case .timeout:
            return true
        case .missingContent, .invalidResponse:
            return false
        }
    }
}

// Add retry wrapper
func sendWithRetry<T>(
    operation: () async throws -> T,
    config: RetryConfiguration
) async throws -> T {
    // Exponential backoff implementation
}
```

### 6. UI Components

**New Views:**

1. **Message Send Status Indicator**
   - Location: Update [`MessageBubble`](TrainerApp/TrainerApp/Views/Chat/MessageBubble.swift)
   - Shows: Sending spinner, retry button, error icon, sent checkmark
   
2. **Retry Button**
   - Inline with failed messages
   - Shows retry count
   - Tap to retry immediately

3. **Offline Banner**
   - Top of chat view when offline
   - Shows queued message count
   - Auto-hides when network returns

## Implementation Plan

### Phase 1: Core Infrastructure (Foundational)

**Files to Create:**
1. `TrainerApp/TrainerApp/Services/NetworkMonitor.swift`
2. `TrainerApp/TrainerApp/Services/MessageRetryManager.swift`
3. `TrainerApp/TrainerApp/Models/SendStatus.swift`

**Files to Modify:**
1. [`ConversationPersistence.swift`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift:33) - Add `sendStatus` to `ChatMessage`
2. [`LLMService.swift`](TrainerApp/TrainerApp/Services/LLMService.swift:5) - Enhanced error types
3. [`PersistenceKey.swift`](TrainerApp/TrainerApp/Persistence/Utilities/PersistenceKey.swift) - Add retry keys

**Deliverables:**
- ✅ Network monitoring active
- ✅ Send status tracking model
- ✅ Retry manager with exponential backoff
- ✅ Enhanced error classification

### Phase 2: Integration with ConversationManager

**Files to Modify:**
1. [`ConversationManager.swift`](TrainerApp/TrainerApp/Services/ConversationManager.swift:7) - Integrate retry manager
2. [`ResponseOrchestrator.swift`](TrainerApp/TrainerApp/Services/ConversationManager/ResponseOrchestrator.swift:31) - Handle retry logic
3. [`MessageFactory.swift`](TrainerApp/TrainerApp/Services/MessageFactory.swift) - Add send status

**Changes:**
```swift
// ConversationManager
@Published private(set) var networkStatus: NetworkStatus = .connected
private let retryManager = MessageRetryManager()

func sendMessage(_ text: String, images: [UIImage] = []) async throws {
    // 1. Create message with .pending status
    // 2. Persist immediately
    // 3. Attempt send via retry manager
    // 4. Update status based on result
}

func retryMessage(_ messageId: UUID) async {
    await retryManager.retryMessage(messageId)
}
```

**Deliverables:**
- ✅ Messages track send status
- ✅ Automatic retries on transient failures
- ✅ Manual retry capability
- ✅ Offline queue processing

### Phase 3: UI Enhancements

**Files to Modify:**
1. [`MessageBubble.swift`](TrainerApp/TrainerApp/Views/Chat/MessageBubble.swift) - Status indicators
2. [`ChatView.swift`](TrainerApp/TrainerApp/Views/Chat/ChatView.swift) - Offline banner
3. [`MessageListView.swift`](TrainerApp/TrainerApp/Views/Chat/MessageListView.swift) - Retry gestures

**New UI Elements:**
- Send status icon (✓, ⟳, ⚠, ...)
- Inline retry button for failed messages
- Offline banner with queue count
- Retry progress indicator

**Deliverables:**
- ✅ Visual send status on messages
- ✅ Tap to retry failed messages
- ✅ Offline mode indicator
- ✅ Clear error messages

### Phase 4: Persistence & Recovery

**Files to Modify:**
1. [`ConversationPersistence.swift`](TrainerApp/TrainerApp/Services/ConversationPersistence.swift:92) - Save/load retry state
2. [`HybridCloudStore.swift`](TrainerApp/TrainerApp/Persistence/Implementations/HybridCloudStore.swift) - Retry state sync

**Features:**
- Persist retry queue across app restarts
- Restore retry state on launch
- Clean up stale retry state
- Sync retry status via iCloud

**Deliverables:**
- ✅ Retry state persists across restarts
- ✅ App recovery from crashes during send
- ✅ Multi-device retry awareness (via iCloud)

## Retry Strategy Details

### Exponential Backoff Algorithm

```swift
func calculateDelay(attempt: Int, config: RetryConfiguration) -> TimeInterval {
    let exponentialDelay = config.baseDelay * pow(config.backoffMultiplier, Double(attempt - 1))
    let jitter = Double.random(in: 0...0.1) * exponentialDelay  // 0-10% jitter
    return min(exponentialDelay + jitter, config.maxDelay)
}

// Example delays:
// Attempt 1: 1.0s + jitter
// Attempt 2: 2.0s + jitter
// Attempt 3: 4.0s + jitter
// Attempt 4+: 30.0s (capped)
```

### Error Classification

| Error Type | Retryable? | Max Retries | Strategy |
|------------|-----------|-------------|----------|
| Network timeout | ✅ Yes | 3 | Exponential backoff |
| 500-599 (Server) | ✅ Yes | 3 | Exponential backoff |
| 429 (Rate limit) | ✅ Yes | 5 | Longer backoff |
| 401 (Auth) | ❌ No | 0 | Manual fix required |
| 400 (Bad request) | ❌ No | 0 | Manual fix required |
| No network | ✅ Yes | ∞ | Wait for network |

### Offline Behavior

1. **Detect offline:** Network monitor reports disconnected
2. **Queue messages:** Store in `offlineQueue` with `.offline` status
3. **Show UI feedback:** Offline banner, queued count
4. **Monitor network:** Wait for `isConnected = true`
5. **Auto-process queue:** Send all queued messages when online
6. **Update UI:** Remove banner, show sending indicators

## Storage Architecture

### Retry State Storage (Tier 2: HybridCloudStore)

```swift
// PersistenceKey additions
enum MessageRetry {
    static func status(_ messageId: UUID) -> String {
        "message_retry_status_\(messageId.uuidString)"
    }
    static let offlineQueue = "message_retry_offline_queue"
}

// Stored structure
struct RetryState: Codable {
    let messageId: UUID
    let attempt: Int
    let lastAttemptDate: Date
    let error: String?
    let status: SendStatus
}
```

### Data Flow

```
User sends message
    ↓
[ChatMessage created with .pending status]
    ↓
[Persisted immediately to conversation history]
    ↓
[Added to RetryManager]
    ↓
[Network check]
    ↓
┌─────────────────┬─────────────────┐
│   Connected     │   Offline       │
└─────────────────┴─────────────────┘
    ↓                  ↓
[Send via LLM]    [Add to queue]
    ↓                  ↓
Success/Failure    [Wait for network]
    ↓                  ↓
Update status      [Auto-send when online]
```

## Testing Strategy

### Unit Tests
- ✅ Retry manager exponential backoff
- ✅ Error classification logic
- ✅ Network monitor state changes
- ✅ Offline queue processing

### Integration Tests
- ✅ End-to-end message send with retry
- ✅ Network loss during send
- ✅ App restart with pending retries
- ✅ iCloud sync of retry state

### Manual Testing Scenarios
1. **Network interruption:** Send message, disable WiFi mid-send
2. **Server error:** Mock 500 response, verify retries
3. **Rate limiting:** Mock 429, verify backoff
4. **Offline queue:** Send 5 messages offline, go online
5. **App restart:** Kill app during retry, verify resume
6. **Manual retry:** Failed message → tap retry → success

## UI Mockups

### Message Status Indicators

```
┌─────────────────────────────────────┐
│ You: Let's plan a workout           │ ← User message
│                              ⟳ 1/3  │ ← Retrying (attempt 1 of 3)
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ You: What's my next workout?        │
│                                 ⚠   │ ← Failed
│ [Tap to retry]                      │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ You: Show me today's schedule       │
│                                 ✓✓  │ ← Sent & delivered
└─────────────────────────────────────┘
```

### Offline Banner

```
┌─────────────────────────────────────┐
│ 🔴 Offline - 3 messages queued      │
│ Messages will send when connected   │
└─────────────────────────────────────┘
```

## Benefits

1. **Reliability:** Messages won't be lost due to transient failures
2. **User Experience:** Clear feedback on message status
3. **Offline Support:** App works offline, syncs when connected
4. **Debugging:** Easy to see why messages failed
5. **Manual Control:** Users can retry failed messages
6. **Cross-device:** Retry state syncs via iCloud

## Risks & Mitigation

### Risk 1: Duplicate Messages
**Scenario:** Message retried, first attempt succeeds late
**Mitigation:** 
- Use message UUID for deduplication
- Server-side idempotency (if available)
- Clear retry state immediately on success

### Risk 2: Infinite Retry Loop
**Scenario:** Non-retryable error marked as retryable
**Mitigation:**
- Max retry limits (3-5 attempts)
- Exponential backoff with max delay
- Clear classification of retryable errors

### Risk 3: Storage Bloat
**Scenario:** Retry state accumulates over time
**Mitigation:**
- Clean up retry state on message completion
- Periodic cleanup of stale retry records (> 7 days)
- Use efficient storage (Tier 2, small payload)

### Risk 4: Network Monitor Battery Drain
**Scenario:** Continuous network monitoring
**Mitigation:**
- Use efficient NWPathMonitor API
- Stop monitoring when app backgrounded
- Resume only when chat view active

## Future Enhancements

### Phase 5 (Optional)
- **Batch retries:** Retry multiple failed messages at once
- **Smart retry:** ML-based retry prediction
- **Priority queue:** Urgent messages retry faster
- **Compression:** Compress large messages before retry
- **Analytics:** Track retry success rates

## Success Metrics

After implementation, we should see:
- ✅ 95%+ message send success rate (including retries)
- ✅ < 1% messages permanently failed
- ✅ Average retry latency < 5 seconds
- ✅ Zero data loss from network failures
- ✅ Positive user feedback on reliability

## Migration Path

### Existing Data
- Existing messages have no `sendStatus` → default to `.sent`
- No breaking changes to storage format
- Backward compatible with old conversation files

### Rollout
1. Deploy with feature flag (disabled by default)
2. Test with beta users (100 users)
3. Monitor retry metrics for 1 week
4. Gradual rollout (25% → 50% → 100%)
5. Enable by default after 2 weeks stable

---

## Questions for Review

1. **Retry limits:** Is 3 attempts appropriate, or should we make it configurable?
2. **UI design:** Should failed messages be visually distinct (e.g., red border)?
3. **Offline queue:** Should we limit queue size (e.g., max 50 messages)?
4. **Error details:** Should users see technical error messages or friendly ones?
5. **Auto-retry:** Should all errors auto-retry, or require manual trigger?

## Next Steps

Once this plan is approved, we can switch to Code mode to implement Phase 1.