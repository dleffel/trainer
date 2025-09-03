import SwiftUI

struct CalendarView: View {
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @State private var viewMode: CalendarViewMode = .week
    @State private var showingProgramSetup = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigationState: NavigationState
    @State private var navigatedToWorkout = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View Mode", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on view mode
                Group {
                    switch viewMode {
                    case .week:
                        WeeklyCalendarView(scheduleManager: scheduleManager)
                    case .month:
                        MonthlyCalendarView(scheduleManager: scheduleManager)
                    }
                }
                
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
            // Check if we need to start a new program
            if scheduleManager.currentProgram == nil {
                showingProgramSetup = true
            }
            
            // Handle deep link navigation
            if let targetDate = navigationState.targetWorkoutDate, !navigatedToWorkout {
                navigatedToWorkout = true
                // Find the workout day for the target date
                if let workoutDay = scheduleManager.currentWeekDays.first(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: targetDate)
                }) {
                    // Switch to week view to show the target day
                    viewMode = .week
                    // Clear the navigation state
                    navigationState.targetWorkoutDate = nil
                }
            }
        }
    }
}

struct MonthlyCalendarView: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var selectedMonth = Date()
    @State private var monthDays: [WorkoutDay] = []
    @State private var selectedDay: WorkoutDay?
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Month selector
                monthSelector
                
                // Calendar grid header
                weekdayHeader
                
                // Calendar grid
                calendarGrid
            }
            .padding()
        }
        .onAppear {
            loadMonth()
        }
        .onChange(of: selectedMonth) { oldValue, newValue in
            loadMonth()
        }
        .sheet(item: $selectedDay) { day in
            WorkoutDetailSheet(day: day, scheduleManager: scheduleManager)
        }
    }
    
    private var monthSelector: some View {
        HStack {
            Button {
                withAnimation {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            
            Spacer()
            
            Text(monthYearText)
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                withAnimation {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
        }
    }
    
    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(calendarDays.enumerated()), id: \.offset) { index, day in
                if let day = day {
                    MonthDayCard(
                        day: day,
                        isToday: calendar.isDateInToday(day.date),
                        isInCurrentMonth: calendar.isDate(day.date, equalTo: selectedMonth, toGranularity: .month)
                    )
                    .onTapGesture {
                        selectedDay = day
                    }
                } else {
                    Color.clear
                        .frame(height: 60)
                }
            }
        }
    }
    
    private var calendarDays: [WorkoutDay?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let paddingDays = firstWeekday - 1
        
        var days: [WorkoutDay?] = Array(repeating: nil, count: paddingDays)
        days.append(contentsOf: monthDays)
        
        return days
    }
    
    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }
    
    private func loadMonth() {
        monthDays = scheduleManager.generateMonth(containing: selectedMonth)
    }
}

struct MonthDayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    let isInCurrentMonth: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.system(size: 14, weight: isToday ? .bold : .medium))
                .foregroundColor(isInCurrentMonth ? .primary : .secondary)
            
            Circle()
                .fill(blockColor)
                .frame(width: 6, height: 6)
            
            if day.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isToday ? 2 : 1)
        )
    }
    
    private var blockColor: Color {
        switch day.blockType {
        case .aerobicCapacity:
            return .blue
        case .hypertrophyStrength:
            return .orange
        case .deload:
            return .green
        case .racePrep:
            return .red
        case .taper:
            return .purple
        }
    }
    
    private var backgroundColor: Color {
        if isToday {
            return Color(.systemBlue).opacity(0.1)
        } else if !isInCurrentMonth {
            return Color(.systemGray6).opacity(0.5)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var borderColor: Color {
        isToday ? .blue : Color(.systemGray5)
    }
}

struct ProgramSetupSheet: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @Environment(\.dismiss) var dismiss
    @State private var startDate = Date()
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
                    Section("Current Program") {
                        HStack {
                            Text("Started")
                            Spacer()
                            Text(programStartDateText)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Current Position")
                            Spacer()
                            Text(scheduleManager.getCurrentPositionDescription())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button {
                        // Adjust to Monday of selected week
                        let calendar = Calendar.current
                        let weekday = calendar.component(.weekday, from: startDate)
                        let daysToMonday = (2 - weekday + 7) % 7
                        let monday = calendar.date(byAdding: .day, value: daysToMonday == 0 ? -7 : -daysToMonday, to: startDate)!
                        
                        scheduleManager.startNewProgram(startDate: monday)
                        dismiss()
                    } label: {
                        Text(scheduleManager.currentProgram == nil ? "Start Program" : "Restart Program")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(scheduleManager.currentProgram == nil ? "New Program" : "Program Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var programStartDateText: String {
        guard let program = scheduleManager.currentProgram else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: program.startDate)
    }
}
        