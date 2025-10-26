import SwiftUI
import UIKit

// MARK: - Message Bubble

/// A chat message bubble that displays user or assistant messages with optional reasoning and attachments.
/// Implements Equatable for performance optimization in message lists.
struct MessageBubble: View, Equatable {
    let messageId: UUID
    let text: String
    let reasoning: String?
    let isUser: Bool
    let isLastMessage: Bool
    @ObservedObject var conversationManager: ConversationManager
    let attachments: [MessageAttachment]?
    let sendStatus: SendStatus?  // NEW: Send status for retry UI
    let messageIndex: Int  // NEW: For retry action
    
    // MARK: - Equatable Conformance
    
    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        // Compare only the properties that affect the visible state
        // Exclude @ObservedObject, @EnvironmentObject, @State, and @AppStorage
        lhs.messageId == rhs.messageId &&
        lhs.text == rhs.text &&
        lhs.reasoning == rhs.reasoning &&
        lhs.isUser == rhs.isUser &&
        lhs.isLastMessage == rhs.isLastMessage &&
        lhs.attachments?.map(\.id) == rhs.attachments?.map(\.id) &&
        lhs.sendStatus == rhs.sendStatus
    }
    
    // MARK: - Environment & State
    
    @EnvironmentObject var navigationState: NavigationState
    @State private var showReasoning = false
    @State private var previewLines: [String] = []
    @State private var lastReasoningLength: Int = 0
    @State private var lastPreviewUpdate: Date = .distantPast
    @AppStorage("ShowAIReasoning") private var showReasoningSetting = false
    
    // MARK: - Computed Properties
    
    /// Get the last few lines of reasoning for preview
    private var reasoningPreview: String {
        guard let reasoning = reasoning else { return "" }
        let lines = reasoning.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(3).joined(separator: "\n")
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Send status indicator (for user messages only)
            if isUser, let status = sendStatus, status != .sent {
                sendStatusView(status)
            }
            // Show reasoning section if available and enabled
            if let reasoning = reasoning, !reasoning.isEmpty, showReasoningSetting {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showReasoning.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.caption)
                        Text("Coach's Thinking")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: showReasoning ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Simple preview when collapsed - show last 3 lines
                if !showReasoning {
                    Text(reasoningPreview)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .italic()
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                }
                
                if showReasoning {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.leading, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Divider()
                    .padding(.vertical, 4)
            }
            
            // Show images if present
            if let attachments = attachments, !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    if attachment.type == .image,
                       let image = UIImage(data: attachment.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            
            // Main message content (only show if there's text)
            if !text.isEmpty {
                LinkDetectingText(text: text, isUser: isUser) { url in
                    handleURL(url)
                }
                .font(.body)
            }
        }
        .foregroundStyle(isUser ? .white : .primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(isUser ? Color.blue : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
    
    // MARK: - Send Status View
    
    @ViewBuilder
    private func sendStatusView(_ status: SendStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .font(.caption)
                .foregroundColor(statusColor(for: status))
            
            Text(status.statusDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Retry button for failed messages
            if status.canRetry {
                Button {
                    Task {
                        try? await conversationManager.retryFailedMessage(at: messageIndex)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.25))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    
    private func statusColor(for status: SendStatus) -> Color {
        switch status {
        case .notSent, .sending:
            return .secondary
        case .sent:
            return .green
        case .retrying:
            return .orange
        case .failed:
            return .red
        case .offline:
            return .yellow
        }
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private func updatePreviewLines() {
        // Use the local reasoning parameter - no array scan needed!
        guard let fullReasoning = reasoning, !fullReasoning.isEmpty else {
            previewLines = []
            lastReasoningLength = 0
            return
        }
        
        // Aggressive throttling: max once per 500ms (2 FPS) to prevent flashing
        let now = Date()
        guard now.timeIntervalSince(lastPreviewUpdate) >= 0.5 else { return }
        
        // Only update if we've accumulated at least 100 more characters since last update
        guard fullReasoning.count >= lastReasoningLength + 100 else { return }
        
        // Split into lines and take the last 5
        let allLines = fullReasoning.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Show last 5 lines
        previewLines = Array(allLines.suffix(5))
        lastReasoningLength = fullReasoning.count
        lastPreviewUpdate = now
    }
    
    private func handleURL(_ url: URL) {
        print("🔗 Chat link tapped: \(url.absoluteString)")
        if url.scheme == "trainer" && url.host == "calendar" {
            // Extract the date from the path
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let dateString = pathComponents.first {
                print("🗓️ Deep link date string: \(dateString)")
                // Parse the date string
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                
                if let date = dateFormatter.date(from: dateString) {
                    print("✅ Parsed deep link date: \(date)")
                    // Set target date first, then switch tab with slight delay
                    // This ensures WeeklyCalendarView receives the target date
                    navigationState.targetWorkoutDate = date
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationState.selectedTab = 1
                    }
                } else {
                    print("❌ Failed to parse deep link date: \(dateString)")
                }
            } else {
                print("❌ No date component found in URL path components: \(url.pathComponents)")
            }
        } else {
            print("⚠️ Unsupported URL tapped: \(url.scheme ?? "nil")://\(url.host ?? "nil")\(url.path)")
        }
    }
}