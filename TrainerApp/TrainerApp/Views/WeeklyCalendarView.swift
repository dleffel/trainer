import SwiftUI

struct WeeklyCalendarView: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var selectedWeek: Date
    @State private var weekDays: [WorkoutDay] = []
    @State private var selectedDay: WorkoutDay?
    @State private var selectedWeekBlock: TrainingBlock?
    @State private var selectedWeekNumber: Int = 1
    @EnvironmentObject var navigationState: NavigationState
    @State private var hasNavigatedToTarget = false
    
    private let calendar = Calendar.current
    
    init(scheduleManager: TrainingScheduleManager) {
        self.scheduleManager = scheduleManager
        // Use the program's start date if current date is before it
        let currentDate = Date.current
        let effectiveDate: Date
        if let programStartDate = scheduleManager.currentProgram?.startDate,
           currentDate < programStartDate {
            effectiveDate = programStartDate
            print("🔍 WeeklyCalendarView.init - Using program start date: \(programStartDate)")
        } else {
            effectiveDate = currentDate
            print("🔍 WeeklyCalendarView.init - Using current date: \(currentDate)")
        }
        _selectedWeek = State(initialValue: effectiveDate)
    }
    
    var body: some View {
        let _ = print("🔍 WeeklyCalendarView.body - Rendering with selectedWeek: \(selectedWeek)")
        let _ = print("🔍 WeeklyCalendarView.body - weekDays count: \(weekDays.count)")
        
        ScrollView {
            VStack(spacing: 16) {
                // Week selector
                weekSelector
                
                // Selected week block info
                if let block = selectedWeekBlock {
                    blockInfoCard(block: block, weekNumber: selectedWeekNumber)
                }
                
                // Days of the week
                weekGrid
                
                // Inline workout details
                if let day = selectedDay {
                    Divider()
                        .padding(.vertical, 8)
                    
                    WorkoutDetailsCard(day: day, scheduleManager: scheduleManager)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .id(day.id) // Force recreation when day changes
                }
            }
            .padding()
        }
        .onAppear {
            print("🔍 WeeklyCalendarView.onAppear - Starting")
            print("🔍 WeeklyCalendarView.onAppear - weekDays count before load: \(weekDays.count)")
            loadWeek()
            print("🔍 WeeklyCalendarView.onAppear - weekDays count after load: \(weekDays.count)")
            
            // Auto-select today if on current week
            if isCurrentWeek, selectedDay == nil {
                print("🔍 WeeklyCalendarView.onAppear - Attempting auto-select for current week")
                if let todayWorkout = weekDays.first(where: { calendar.isDate($0.date, inSameDayAs: Date.current) }) {
                    print("🔍 WeeklyCalendarView.onAppear - Found today's workout, selecting")
                    selectedDay = todayWorkout
                } else {
                    print("🔍 WeeklyCalendarView.onAppear - No workout found for today")
                }
            }
            handleDeepLinkNavigation()
        }
        .onChange(of: selectedWeek) { oldValue, newValue in
            loadWeek()
            // Clear selection when changing weeks
            selectedDay = nil
        }
        .onChange(of: navigationState.targetWorkoutDate) { _, _ in
            handleDeepLinkNavigation()
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
                DayCard(day: day, 
       isToday: calendar.isDate(day.date, inSameDayAs: Date.current),
       isSelected: selectedDay?.id == day.id)
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
              let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: Date.current) else {
            return false
        }
        
        return weekInterval.start == currentWeekInterval.start
    }
    
    private func loadWeek() {
        print("🔍 DEBUG - Loading week for date: \(selectedWeek)")
        print("🔍 DEBUG - Is current week: \(isCurrentWeek)")
        print("🔍 DEBUG - scheduleManager.currentWeekDays count: \(scheduleManager.currentWeekDays.count)")
        
        let generatedDays = scheduleManager.generateWeek(containing: selectedWeek)
        print("🔍 DEBUG - Generated \(generatedDays.count) days from generateWeek")
        
        weekDays = generatedDays
        
        // DEBUG: Check if any days have workout data
        print("📅 WeeklyCalendarView loadWeek - Got \(weekDays.count) days")
        var daysWithWorkouts = 0
        for day in weekDays {
            if day.plannedWorkout != nil {
                daysWithWorkouts += 1
                print("  ✅ \(day.dayOfWeek.name): Has workout - \(String(day.plannedWorkout?.prefix(30) ?? ""))")
            } else {
                print("  ❌ \(day.dayOfWeek.name): NO workout data")
            }
        }
        print("📅 WeeklyCalendarView - Summary: \(daysWithWorkouts)/\(weekDays.count) days have workouts")
        
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
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Text(day.dayOfWeek.shortName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.title3)
                .fontWeight(isToday || isSelected ? .bold : .medium)
            
            Image(systemName: day.dayOfWeek.workoutIcon(for: day.blockType))
                .font(.system(size: 20))
                .foregroundColor(workoutIconColor)
            
            // Status indicators row
            HStack(spacing: 4) {
                if day.dayOfWeek == .monday {
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
                .stroke(borderColor, lineWidth: borderLineWidth)
        )
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color(.systemBlue).opacity(0.2)
        } else if isToday {
            return Color(.systemBlue).opacity(0.1)
        } else if day.dayOfWeek == .monday {
            return Color(.systemGray6)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue.opacity(0.5)
        } else {
            return .clear
        }
    }
    
    private var borderLineWidth: CGFloat {
        if isSelected {
            return 2
        } else if isToday {
            return 1
        } else {
            return 0
        }
    }
    
    private var workoutIconColor: Color {
        if day.dayOfWeek == .monday {
            return .indigo
        } else {
            return .primary
        }
    }
}

struct WorkoutDetailsCard: View {
    let day: WorkoutDay
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with day info and collapse button
            HStack {
                Image(systemName: day.dayOfWeek.workoutIcon(for: day.blockType))
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.dayOfWeek.name)")
                        .font(.headline)
                    Text(dateFormatter.string(from: day.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.systemGray5)))
                }
            }
            
            // Collapsible content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let workout = day.plannedWorkout {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Planned Workout", systemImage: "calendar")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Text(workout)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    } else {
                        HStack {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundColor(.orange)
                            Text("No workout planned yet")
                                .font(.body)
                                .italic()
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(.secondary.opacity(0.3))
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
}