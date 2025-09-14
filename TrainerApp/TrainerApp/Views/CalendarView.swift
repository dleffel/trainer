import SwiftUI

struct CalendarView: View {
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @State private var navigatedToWorkout = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Weekly calendar view
                WeeklyCalendarView(scheduleManager: scheduleManager)
                
                Spacer()
            }
            .navigationTitle("Training Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Handle deep link navigation
            if let targetDate = navigationState.targetWorkoutDate, !navigatedToWorkout {
                print("🧭 CalendarView detected deep link target: \(targetDate)")
                navigatedToWorkout = true
                // Pass navigation handling to WeeklyCalendarView
                print("🧭 CalendarView passing navigation to WeeklyCalendarView via navigationState")
            }
        }
    }
}
