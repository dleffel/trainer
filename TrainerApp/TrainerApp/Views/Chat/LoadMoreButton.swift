import SwiftUI

/// Button component for loading older messages in the chat
struct LoadMoreButton: View {
    let availableCount: Int
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle")
                        .font(.body)
                }
                
                Text(isLoading ? "Loading..." : "Load \(availableCount) older message\(availableCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadMoreButton(availableCount: 25, isLoading: false, action: {})
        LoadMoreButton(availableCount: 10, isLoading: false, action: {})
        LoadMoreButton(availableCount: 1, isLoading: false, action: {})
        LoadMoreButton(availableCount: 25, isLoading: true, action: {})
    }
    .padding()
}