import SwiftUI

// MARK: - Chat State Enum
enum ChatState: Equatable {
    case idle
    case preparingResponse
    case streaming(progress: String?)
    case processingTool(name: String, description: String)
    case finalizing
}

// MARK: - Tool Descriptions
struct ToolDescription {
    let icon: String
    let description: String
}

let toolDescriptions: [String: ToolDescription] = [
    "get_training_status": ToolDescription(
        icon: "figure.run",
        description: "Checking your training status..."
    ),
    "start_training_program": ToolDescription(
        icon: "calendar.badge.plus",
        description: "Setting up your program..."
    ),
    "plan_week_workouts": ToolDescription(
        icon: "calendar",
        description: "Planning your week..."
    ),
    "generate_workout_instructions": ToolDescription(
        icon: "doc.text",
        description: "Creating workout details..."
    ),
    "get_user_age": ToolDescription(
        icon: "person.crop.circle",
        description: "Checking your profile..."
    ),
    "get_current_week_summary": ToolDescription(
        icon: "chart.bar",
        description: "Getting this week's summary..."
    ),
    "get_metrics_summary": ToolDescription(
        icon: "chart.line.uptrend.xyaxis",
        description: "Analyzing your metrics..."
    ),
    "check_health_data": ToolDescription(
        icon: "heart.text.square",
        description: "Checking health data..."
    )
]

// MARK: - Chat Status View
struct ChatStatusView: View {
    let state: ChatState
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
                
            case .preparingResponse:
                StatusBubble(
                    icon: "ellipsis.circle",
                    text: "Thinking..."
                )
                
            case .streaming(let preview):
                if let preview = preview, !preview.isEmpty {
                    StatusBubble(
                        icon: "text.bubble",
                        text: preview
                    )
                } else {
                    EnhancedTypingIndicator()
                }
                
            case .processingTool(_, let description):
                StatusBubble(
                    icon: "gearshape.2.fill",
                    text: description
                )
                
            case .finalizing:
                StatusBubble(
                    icon: "checkmark.circle",
                    text: "Finalizing..."
                )
            }
        }
        .id("status-indicator")
    }
}

// MARK: - Status Bubble Component
struct StatusBubble: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            // Static icon (no animations to prevent scroll interference)
            ZStack {
                // Icon container
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 1)
                    )
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor.gradient)
            }
            
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        .frame(maxWidth: 280, alignment: .leading)
    }
    
    private var statusColor: Color {
        // Color based on the type of status
        if text.contains("Thinking") || text.contains("Preparing") {
            return .blue
        } else if text.contains("Finalizing") || text.contains("Complete") {
            return .green
        } else if text.contains("Processing") || text.contains("Creating") {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Enhanced Typing Indicator
struct EnhancedTypingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        .frame(maxWidth: 100, alignment: .leading)
    }
}

// MARK: - Network Activity Indicator
struct NetworkActivityView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Tool Helper Functions
extension ChatState {
    static func toolState(for toolName: String) -> ChatState {
        let description = toolDescriptions[toolName]?.description ?? "Processing \(toolName)..."
        return .processingTool(name: toolName, description: description)
    }
}