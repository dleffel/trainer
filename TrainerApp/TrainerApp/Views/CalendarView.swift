import SwiftUI

struct CalendarView: View {
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @State private var showingProgramSetup = false
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if scheduleManager.currentProgram == nil {
                            Button {
                                showingProgramSetup = true
                            } label: {
                                Label("Start New Program", systemImage: "plus.circle")
                            }
                        } else {
                            Button {
                                showingProgramSetup = true
                            } label: {
                                Label("Program Settings", systemImage: "gearshape")
                            }
                            
                            if scheduleManager.currentProgram?.raceDate == nil {
                                Button {
                                    // Add race scheduling
                                } label: {
                                    Label("Schedule Race", systemImage: "flag.checkered")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingProgramSetup) {
                ProgramSetupSheet(scheduleManager: scheduleManager)
            }
        }
        .onAppear {
            print("🧭 CalendarView.onAppear - program nil? \(scheduleManager.currentProgram == nil ? "yes" : "no")")
            // Check if we need to start a new program
            if scheduleManager.currentProgram == nil {
                showingProgramSetup = true
            }
            
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


struct ProgramSetupSheet: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @Environment(\.dismiss) var dismiss
    @State private var startDate = Date.current
    @State private var showingDatePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Program Start Date") {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    
                    Text("The program will begin on Monday of the selected week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if scheduleManager.currentProgram != nil {
                    HStack {
                        Text("Started")
                        Spacer()
                        Text(programStartDateText)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Current Position")
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let block = scheduleManager.currentBlock {
                                Text("\(block.type.rawValue)")
                                    .font(.caption)
                                Text("Week \(scheduleManager.currentWeekInBlock) of \(block.type.duration)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(scheduleManager.currentProgram == nil ? "Start New Program" : "Program Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scheduleManager.currentProgram == nil ? "Start" : "Update") {
                        scheduleManager.startProgram(startDate: startDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var programStartDateText: String {
        guard let program = scheduleManager.currentProgram else { return "Not started" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: program.startDate)
    }
}
