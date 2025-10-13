import SwiftUI

// MARK: - Calendar Tab View

/// Calendar tab view that displays the weekly calendar and handles deep linking navigation.
/// Combines the log tab navigation with calendar content.
struct CalendarTabView: View {
    @Binding var showSettings: Bool
    
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @EnvironmentObject var navigationState: NavigationState
    @State private var navigatedToWorkout = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeeklyCalendarView(scheduleManager: scheduleManager)
                Spacer()
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear {
                // Handle deep link navigation
                if let targetDate = navigationState.targetWorkoutDate, !navigatedToWorkout {
                    print("🧭 CalendarTabView detected deep link target: \(targetDate)")
                    navigatedToWorkout = true
                    // Pass navigation handling to WeeklyCalendarView
                    print("🧭 CalendarTabView passing navigation to WeeklyCalendarView via navigationState")
                }
            }
        }
    }
}