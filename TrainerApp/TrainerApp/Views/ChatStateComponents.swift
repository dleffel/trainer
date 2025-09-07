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
    @State private var isAnimating = false
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
                
            case .preparingResponse:
                StatusBubble(
                    icon: "ellipsis.circle",
                    text: "Thinking...",
                    isAnimating: true
                )
                
            case .streaming(let preview):
                if let preview = preview, !preview.isEmpty {
                    StatusBubble(
                        icon: "text.bubble",
                        text: preview,
                        isAnimating: true
                    )
                } else {
                    EnhancedTypingIndicator()
                }
                
            case .processingTool(_, let description):
                StatusBubble(
                    icon: "gearshape.2.fill",
                    text: description,
                    isAnimating: true
                )
                
            case .finalizing:
                StatusBubble(
                    icon: "checkmark.circle",
                    text: "Finalizing...",
                    isAnimating: false
                )
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.3), value: state)
        .id("status-indicator")
    }
}

// MARK: - Status Bubble Component
struct StatusBubble: View {
    let icon: String
    let text: String
    let isAnimating: Bool
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isAnimating ? rotation : 0))
                .onAppear {
                    if isAnimating {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
                }
            
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 250, alignment: .leading)
    }
}

// MARK: - Enhanced Typing Indicator
struct EnhancedTypingIndicator: View {
    @State private var animatingDots = [false, false, false]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animatingDots[index] ? 1.2 : 0.8)
                    .opacity(animatingDots[index] ? 1.0 : 0.5)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 80, alignment: .leading)
        .onAppear {
            animateDots()
        }
    }
    
    private func animateDots() {
        for index in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    animatingDots[index] = true
                }
            }
        }
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