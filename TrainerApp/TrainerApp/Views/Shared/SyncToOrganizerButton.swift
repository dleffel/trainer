import SwiftUI

/// Button component for syncing a workout day to the Organizer Exercise API
/// Shows progress, success, and error states with appropriate feedback
struct SyncToOrganizerButton: View {
    let day: WorkoutDay
    @ObservedObject var scheduleManager: TrainingScheduleManager
    
    @StateObject private var syncService = DaySyncService.shared
    @State private var isSyncing = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showCredentialsAlert = false
    @State private var syncError: Error?
    
    private let credentials = ExerciseAPICredentials.shared
    
    var body: some View {
        VStack(spacing: 8) {
            Button {
                performSync()
            } label: {
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(foregroundColor)
                        Text(syncService.status.description)
                    } else if showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Synced to Organizer")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync to Organizer")
                    }
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(10)
            }
            .disabled(isSyncing || !day.hasWorkout)
            .opacity(day.hasWorkout ? 1.0 : 0.5)
            
            // Hint text when no credentials
            if !credentials.hasCredentials && !isSyncing {
                Text("Configure Organizer credentials in Settings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .alert("Organizer Credentials Required", isPresented: $showCredentialsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please configure your Organizer email and app password in Settings → Organizer API section.")
        }
        .alert("Sync Failed", isPresented: $showError) {
            Button("Retry") {
                performSync()
            }
            Button("Cancel", role: .cancel) {
                syncService.reset()
            }
        } message: {
            Text(syncError?.localizedDescription ?? "An unknown error occurred. Please try again.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        if showSuccess {
            return Color.green.opacity(0.15)
        } else if isSyncing {
            return Color.accentColor.opacity(0.1)
        }
        return Color.accentColor.opacity(0.15)
    }
    
    private var foregroundColor: Color {
        if showSuccess {
            return .green
        }
        return .accentColor
    }
    
    // MARK: - Actions
    
    private func performSync() {
        // Check credentials first
        guard credentials.hasCredentials else {
            showCredentialsAlert = true
            return
        }
        
        // Check for workout data
        guard day.hasWorkout else {
            return
        }
        
        isSyncing = true
        showSuccess = false
        syncError = nil
        
        Task {
            do {
                try await syncService.syncDay(day)
                
                await MainActor.run {
                    isSyncing = false
                    showSuccess = true
                    
                    // Haptic feedback for success
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // Reset success indicator after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showSuccess = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncError = error
                    showError = true
                    
                    // Haptic feedback for error
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("With Workout") {
    let sampleDay = WorkoutDay(
        date: Date(),
        blockType: .hypertrophyStrength,
        plannedWorkout: "Upper Body Strength"
    )
    
    VStack {
        SyncToOrganizerButton(
            day: sampleDay,
            scheduleManager: TrainingScheduleManager.shared
        )
        .padding()
    }
}

#Preview("No Workout") {
    let sampleDay = WorkoutDay(
        date: Date(),
        blockType: .hypertrophyStrength
    )
    
    VStack {
        SyncToOrganizerButton(
            day: sampleDay,
            scheduleManager: TrainingScheduleManager.shared
        )
        .padding()
    }
}
