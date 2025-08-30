import SwiftUI

struct WeeklyCalendarView: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var selectedWeek = Date()
    @State private var weekDays: [WorkoutDay] = []
    @State private var selectedDay: WorkoutDay?
    @State private var selectedWeekBlock: TrainingBlock?
    @State private var selectedWeekNumber: Int = 1
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 16) {
            // Week selector
            weekSelector
            
            // Selected week block info
            if let block = selectedWeekBlock {
                blockInfoCard(block: block, weekNumber: selectedWeekNumber)
            }
            
            // Days of the week
            weekGrid
        }
        .padding()
        .onAppear {
            loadWeek()
        }
        .onChange(of: selectedWeek) { oldValue, newValue in
            loadWeek()
        }
        .sheet(item: $selectedDay) { day in
            WorkoutDetailSheet(day: day, scheduleManager: scheduleManager)
        }
    }
    
    private var weekSelector: some View {
        HStack {
            Button {
                withAnimation {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text(weekRangeText)
                    .font(.headline)
                
                if isCurrentWeek {
                    Text("Current Week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                withAnimation {
                    selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
        }
    }
    
    private func blockInfoCard(block: TrainingBlock, weekNumber: Int) -> some View {
        HStack {
            Image(systemName: block.type.icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color(block.type.color))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(block.type.rawValue)
                    .font(.headline)
                Text("Week \(weekNumber) of \(block.type.duration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let daysUntilDeload = calculateDaysUntilDeload(from: selectedWeek, block: block), daysUntilDeload > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(daysUntilDeload)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("days to deload")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func calculateDaysUntilDeload(from date: Date, block: TrainingBlock) -> Int? {
        guard block.type != .deload else { return 0 }
        
        let calendar = Calendar.current
        let daysUntilBlockEnd = calendar.dateComponents([.day], from: date, to: block.endDate).day ?? 0
        return max(0, daysUntilBlockEnd)
    }
    
    private var weekGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
            ForEach(weekDays) { day in
                DayCard(day: day, isToday: calendar.isDateInToday(day.date))
                    .onTapGesture {
                        selectedDay = day
                    }
            }
        }
    }
    
    private var weekRangeText: String {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedWeek),
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: weekInterval.start) else {
            return "Week"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        return "\(formatter.string(from: weekInterval.start)) - \(formatter.string(from: endOfWeek))"
    }
    
    private var isCurrentWeek: Bool {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedWeek),
              let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return false
        }
        
        return weekInterval.start == currentWeekInterval.start
    }
    
    private func loadWeek() {
        print("🔍 DEBUG - Loading week for date: \(selectedWeek)")
        
        weekDays = scheduleManager.generateWeek(containing: selectedWeek)
        
        // Calculate block info for selected week
        if let program = scheduleManager.currentProgram {
            let calendar = Calendar.current
            let weeksSinceStart = calendar.dateComponents([.weekOfYear],
                                                         from: program.startDate,
                                                         to: selectedWeek).weekOfYear ?? 0
            let totalWeek = weeksSinceStart + 1
            print("🔍 DEBUG - Weeks since program start: \(totalWeek)")
            
            // Get block info for this week
            let blockInfo = scheduleManager.getBlockForWeek(totalWeek)
            selectedWeekNumber = blockInfo.weekInBlock
            
            // Get the actual block for this date
            if let block = scheduleManager.getBlockForDate(selectedWeek) {
                selectedWeekBlock = block
                print("🔍 DEBUG - Selected week is: \(block.type.rawValue) - Week \(selectedWeekNumber)")
            }
        }
    }
}

struct DayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Text(day.dayOfWeek.shortName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.title3)
                .fontWeight(isToday ? .bold : .medium)
            
            Image(systemName: day.dayOfWeek.workoutIcon(for: day.blockType))
                .font(.system(size: 20))
                .foregroundColor(workoutIconColor)
            
            if day.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else if day.dayOfWeek == .monday {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isToday ? 2 : 0)
        )
    }
    
    private var backgroundColor: Color {
        if isToday {
            return Color(.systemBlue).opacity(0.1)
        } else if day.dayOfWeek == .monday {
            return Color(.systemGray6)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var borderColor: Color {
        isToday ? .blue : .clear
    }
    
    private var workoutIconColor: Color {
        if day.completed {
            return .green
        } else if day.dayOfWeek == .monday {
            return .indigo
        } else {
            return .primary
        }
    }
}

struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let day: WorkoutDay
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var notes: String = ""
    @State private var actualWorkout: String = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: day.dayOfWeek.workoutIcon(for: day.blockType))
                                .font(.title)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(day.dayOfWeek.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(dateFormatter.string(from: day.date))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if day.completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Planned workout
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Planned Workout", systemImage: "calendar")
                            .font(.headline)
                        
                        Text(day.plannedWorkout ?? "Rest Day")
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    
                    // Actual workout (if completed)
                    if day.completed, let actualWorkout = day.actualWorkout, !actualWorkout.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Actual Workout", systemImage: "figure.strengthtraining.traditional")
                                .font(.headline)
                            
                            Text(actualWorkout)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Notes
                    if day.completed, let notes = day.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)
                            
                            Text(notes)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Completion toggle
                    if !Calendar.current.isDate(day.date, inSameDayAs: Date()) && day.date < Date() {
                        VStack(spacing: 16) {
                            Toggle("Mark as Completed", isOn: .constant(day.completed))
                                .disabled(true)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                            
                            if !day.completed {
                                Button {
                                    scheduleManager.markWorkoutCompleted(for: day)
                                    dismiss()
                                } label: {
                                    Label("Mark as Completed", systemImage: "checkmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    scheduleManager.markWorkoutIncomplete(for: day)
                                    dismiss()
                                } label: {
                                    Label("Mark as Incomplete", systemImage: "xmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top)
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            notes = day.notes ?? ""
            actualWorkout = day.actualWorkout ?? ""
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
}