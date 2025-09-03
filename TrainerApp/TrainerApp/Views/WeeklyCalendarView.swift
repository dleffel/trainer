import SwiftUI

struct WeeklyCalendarView: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var selectedWeek = Date()
    @State private var weekDays: [WorkoutDay] = []
    @State private var selectedDay: WorkoutDay?
    @State private var selectedWeekBlock: TrainingBlock?
    @State private var selectedWeekNumber: Int = 1
    @EnvironmentObject var navigationState: NavigationState
    @State private var hasNavigatedToTarget = false
    
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
            handleDeepLinkNavigation()
        }
        .onChange(of: selectedWeek) { oldValue, newValue in
            loadWeek()
        }
        .onChange(of: navigationState.targetWorkoutDate) { _, _ in
            handleDeepLinkNavigation()
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
    
    private func handleDeepLinkNavigation() {
        guard let targetDate = navigationState.targetWorkoutDate,
              !hasNavigatedToTarget else { return }
        
        // Mark as navigated to prevent loops
        hasNavigatedToTarget = true
        
        // Navigate to the week containing the target date
        selectedWeek = targetDate
        loadWeek()
        
        // Find and select the workout day
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let targetDay = weekDays.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: targetDate)
            }) {
                selectedDay = targetDay
                navigationState.targetWorkoutDate = nil
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
            
            // Status indicators row
            HStack(spacing: 4) {
                if day.detailedInstructions != nil {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                
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
    @State private var showingInstructions = false
    
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
                    
                    // Detailed Instructions (if available)
                    if let instructions = day.detailedInstructions {
                        DetailedInstructionsCard(
                            instructions: instructions,
                            isExpanded: $showingInstructions
                        )
                    }
                    
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
            // Auto-expand instructions if navigated from deep link
            if day.detailedInstructions != nil {
                showingInstructions = true
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Detailed Instructions Components

struct DetailedInstructionsCard: View {
    let instructions: WorkoutInstructions
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Detailed Instructions", systemImage: "doc.text.fill")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(instructions.sections.indices, id: \.self) { index in
                        InstructionSectionView(section: instructions.sections[index])
                        
                        if index < instructions.sections.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } else {
                HStack {
                    Text("Tap to view detailed workout instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Generated \(relativeTimeString(from: instructions.generatedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct InstructionSectionView: View {
    let section: InstructionSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.content.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                            .font(.body)
                        Text(section.content[index])
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}