import SwiftUI
import UIKit

// MARK: - Supporting Components

/// Compact summary view for workout header showing key details as chips
struct WorkoutSummaryView: View {
    let title: String?
    let duration: Int?
    let rpe: String?
    let modality: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
            }
            
            // Horizontal chip layout for key stats
            HStack(spacing: 8) {
                if let duration = duration {
                    Chip(text: "\(duration) min", color: .blue)
                }
                if let rpe = rpe {
                    Chip(text: rpe, color: .orange)
                }
                if let modality = modality {
                    Chip(text: modality, color: .purple)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(12)
    }
    
    private func workoutIcon(for modality: String) -> String {
        let lower = modality.lowercased()
        if lower.contains("bike") || lower.contains("cycling") {
            return "bicycle"
        } else if lower.contains("run") {
            return "figure.run"
        } else if lower.contains("swim") {
            return "figure.pool.swim"
        } else if lower.contains("strength") || lower.contains("lift") {
            return "dumbbell"
        } else if lower.contains("yoga") {
            return "figure.yoga"
        } else if lower.contains("mobility") {
            return "figure.flexibility"
        }
        return "figure.mixed.cardio"
    }
}

/// Collapsible coaching notes view that defaults to collapsed state
struct CoachingNotesView: View {
    let notes: String
    @State private var isExpanded = false
    
    private var shouldTruncate: Bool {
        notes.count > 200 // Threshold for truncation
    }
    
    private var displayText: String {
        if shouldTruncate && !isExpanded {
            return String(notes.prefix(200)) + "..."
        }
        return notes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                    Text("Coaching Notes")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.secondary)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
            .accessibilityLabel("Coaching notes")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
            .accessibilityAddTraits(.isHeader)
            
            if isExpanded {
                Text(displayText)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
                    .accessibilityLabel("Coaching notes: \(displayText)")
                
                if shouldTruncate {
                    Button {
                        withAnimation {
                            isExpanded = false
                        }
                    } label: {
                        Text("Read Less")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }
}

/// Condensed program context banner for workout detail view
struct ProgramContextBanner: View {
    let blockType: BlockType
    let weekNumber: Int
    let totalWeeks: Int
    let daysToDeload: Int?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: blockType.icon)
                .font(.caption)
                .foregroundStyle(blockGradient(for: blockType))
            
            Text("Week \(weekNumber)/\(totalWeeks)")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            Text("•")
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(blockType.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let days = daysToDeload, days > 0 {
                Spacer()
                Text("\(days)d to deload")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func blockGradient(for type: BlockType) -> LinearGradient {
        let colors: [Color]
        switch type.rawValue.lowercased() {
        case let value where value.contains("hypertrophy"):
            colors = [.blue, .purple]
        case let value where value.contains("strength"):
            colors = [.red, .orange]
        case let value where value.contains("deload"):
            colors = [.green, .teal]
        default:
            colors = [.blue, .cyan]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Weekly Calendar View

struct WeeklyCalendarView: View {
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @State private var selectedWeek: Date
    @State private var weekDays: [WorkoutDay] = []
    @State private var selectedDay: WorkoutDay?
    @State private var selectedWeekBlock: TrainingBlock?
    @State private var selectedWeekNumber: Int = 1
    @EnvironmentObject var navigationState: NavigationState
    @State private var hasNavigatedToTarget = false
    @State private var isLoadingWeek = false
    @State private var swipeDirection: SwipeDirection = .none
    
    private let calendar = Calendar.current
    
    enum SwipeDirection {
        case left, right, none
    }
    
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
        
        ScrollViewReader { proxy in
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
                            .id("workout-detail-\(day.id)") // Unique ID per day for proper transitions
                            .transition(slideTransition(for: swipeDirection))
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedDay?.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: selectedDay?.id) { oldValue, newValue in
                if let dayId = newValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("workout-detail-\(dayId)", anchor: .top)
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onChanged { value in
                    // Provide visual hint during drag
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    guard horizontalAmount > verticalAmount, horizontalAmount > 30 else { return }
                    
                    // Set direction preview
                    if value.translation.width < 0 {
                        swipeDirection = .left
                    } else {
                        swipeDirection = .right
                    }
                }
                .onEnded { value in
                    // Only trigger on horizontal swipes (not vertical scrolls)
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    guard horizontalAmount > verticalAmount else {
                        swipeDirection = .none
                        return
                    }
                    
                    // Navigate day-to-day if a day is selected, otherwise week-to-week
                    if let currentDay = selectedDay {
                        if value.translation.width < -50 {
                            // Swipe left = next day
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            navigateToNextDay(from: currentDay)
                        } else if value.translation.width > 50 {
                            // Swipe right = previous day
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            navigateToPreviousDay(from: currentDay)
                        }
                    } else {
                        // No day selected, navigate week-to-week
                        if value.translation.width < -50 {
                            // Swipe left = next week
                            withAnimation {
                                selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
                            }
                        } else if value.translation.width > 50 {
                            // Swipe right = previous week
                            withAnimation {
                                selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
                            }
                        }
                    }
                    
                    // Reset direction after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        swipeDirection = .none
                    }
                }
        )
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous week")
            .accessibilityHint("Navigate to earlier workouts")
            
            Spacer()
            
            VStack(spacing: 4) {
                Text(weekRangeText)
                    .font(.headline)
                
                if isCurrentWeek {
                    Text("Current Week")
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.6))
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next week")
            .accessibilityHint("Navigate to later workouts")
        }
    }
    
    private func blockInfoCard(block: TrainingBlock, weekNumber: Int) -> some View {
        HStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(blockGradient(for: block.type))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                
                Image(systemName: block.type.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Block info
            VStack(alignment: .leading, spacing: 4) {
                Text(block.type.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Week \(weekNumber) of \(block.type.duration)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Days to deload indicator
            if let daysUntilDeload = calculateDaysUntilDeload(from: selectedWeek, block: block),
               daysUntilDeload > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(daysUntilDeload)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("days to deload")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            blockGradient(for: block.type).opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.type.rawValue) phase, week \(weekNumber) of \(block.type.duration)")
    }
    
    private func blockGradient(for type: BlockType) -> LinearGradient {
        let colors: [Color]
        switch type.rawValue.lowercased() {
        case let value where value.contains("hypertrophy"):
            colors = [.blue, .purple]
        case let value where value.contains("strength"):
            colors = [.red, .orange]
        case let value where value.contains("deload"):
            colors = [.green, .teal]
        default:
            colors = [.blue, .cyan]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func calculateDaysUntilDeload(from date: Date, block: TrainingBlock) -> Int? {
        guard block.type != .deload else { return 0 }
        
        let calendar = Calendar.current
        let daysUntilBlockEnd = calendar.dateComponents([.day], from: date, to: block.endDate).day ?? 0
        return max(0, daysUntilBlockEnd)
    }
    
    private var weekGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(weekDays) { day in
                DayCard(day: day,
                       isToday: calendar.isDate(day.date, inSameDayAs: Date.current),
                       isSelected: selectedDay?.id == day.id)
                    .onTapGesture {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDay = day
                        }
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
        isLoadingWeek = true
        defer { isLoadingWeek = false }
        
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
            
            // DIAGNOSTIC LOGGING
            print("🔍 DIAGNOSTIC - Program start date: \(program.startDate)")
            print("🔍 DIAGNOSTIC - Selected week date: \(selectedWeek)")
            print("🔍 DIAGNOSTIC - Start of selected week: \(calendar.dateInterval(of: .weekOfYear, for: selectedWeek)?.start ?? selectedWeek)")
            
            let weeksSinceStart = calendar.dateComponents([.weekOfYear],
                                                         from: program.startDate,
                                                         to: selectedWeek).weekOfYear ?? 0
            let totalWeek = weeksSinceStart + 1
            print("🔍 DEBUG - weeksSinceStart: \(weeksSinceStart), totalWeek: \(totalWeek)")
            
            // Get block info for this week
            let blockInfo = scheduleManager.getBlockForWeek(totalWeek)
            selectedWeekNumber = blockInfo.weekInBlock
            print("🔍 DIAGNOSTIC - getBlockForWeek(\(totalWeek)) returned: \(blockInfo.type.rawValue), week \(blockInfo.weekInBlock)")
            
            // Get the actual block for this date
            if let block = scheduleManager.getBlockForDate(selectedWeek) {
                selectedWeekBlock = block
                print("🔍 DEBUG - Selected week is: \(block.type.rawValue) - Week \(selectedWeekNumber)")
            } else {
                print("🔍 DIAGNOSTIC - WARNING: getBlockForDate(\(selectedWeek)) returned nil!")
            }
        }
    }
    
    private func navigateToNextDay(from currentDay: WorkoutDay) {
        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDay.date) else { return }
        
        // Set direction before changing selection
        swipeDirection = .left
        
        // Check if next day is in current week
        if let nextDay = weekDays.first(where: { calendar.isDate($0.date, inSameDayAs: nextDate) }) {
            // Next day is in current week
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedDay = nextDay
            }
        } else {
            // Next day is in next week
            withAnimation {
                selectedWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeek) ?? selectedWeek
            }
            // After week loads, select the first day
            DispatchQueue.main.async {
                if let firstDay = weekDays.first {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedDay = firstDay
                    }
                }
            }
        }
    }
    
    private func navigateToPreviousDay(from currentDay: WorkoutDay) {
        guard let prevDate = calendar.date(byAdding: .day, value: -1, to: currentDay.date) else { return }
        
        // Set direction before changing selection
        swipeDirection = .right
        
        // Check if previous day is in current week
        if let prevDay = weekDays.first(where: { calendar.isDate($0.date, inSameDayAs: prevDate) }) {
            // Previous day is in current week
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedDay = prevDay
            }
        } else {
            // Previous day is in previous week
            withAnimation {
                selectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeek) ?? selectedWeek
            }
            // After week loads, select the last day
            DispatchQueue.main.async {
                if let lastDay = weekDays.last {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedDay = lastDay
                    }
                }
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
    
    private func slideTransition(for direction: SwipeDirection) -> AnyTransition {
        switch direction {
        case .left:
            // Swiping left = next day
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .right:
            // Swiping right = previous day
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .none:
            // Fallback for programmatic selection (e.g., tapping day cards)
            return .scale(scale: 0.95).combined(with: .opacity)
        }
    }
}

struct DayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            // Day abbreviation
            Text(day.dayOfWeek.shortName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Day number
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.system(size: 20, weight: isToday ? .bold : .semibold, design: .rounded))
                .foregroundColor(isToday ? .white : .primary)
            
            // Workout icon with gradient
            if day.hasWorkout {
                Image(systemName: workoutIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(workoutStatusGradient)
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray.gradient)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
                
                // Today indicator with gradient
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Selection overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(day.hasWorkout ? "Double tap to view workout details" : "No workout planned")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var backgroundColor: Color {
        if isToday {
            return .clear // Gradient handles today background
        } else if day.hasWorkout && !(day.displaySummary?.isEmpty ?? true) {
            // Subtle tint for completed workouts
            return Color.green.opacity(0.1)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
    
    private var workoutStatusGradient: LinearGradient {
        // Check if workout appears completed (has summary/results)
        let hasResults = day.displaySummary != nil && !day.displaySummary!.isEmpty
        
        if hasResults {
            return LinearGradient(
                colors: [.green, .green.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.orange, .orange.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isToday {
            return Color.accentColor.opacity(0.5)
        } else {
            return .clear
        }
    }
    
    private var accessibilityText: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateText = dateFormatter.string(from: day.date)
        let workoutDescription = day.hasWorkout ? (day.displaySummary ?? "Workout planned") : "Rest day"
        return "\(day.dayOfWeek.name), \(dateText), \(workoutDescription)"
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
    
    private var workoutIcon: String {
        return day.displayIcon
    }
    
    private var workoutIconColor: Color {
        if day.hasWorkout {
            return .primary  // Has workout
        } else {
            return .orange  // No workout planned
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
            HStack(spacing: 12) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: day.displayIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.dayOfWeek.name)")
                        .font(.system(size: 20, weight: .semibold))
                    Text(dateFormatter.string(from: day.date))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    if let summary = day.displaySummary {
                        Text(summary)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue.gradient)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            }
            
            // NEW: Add program context banner below header
            if let block = scheduleManager.getBlockForDate(day.date),
               let program = scheduleManager.currentProgram {
                let calendar = Calendar.current
                let weeksSinceStart = calendar.dateComponents([.weekOfYear],
                                                             from: program.startDate,
                                                             to: day.date).weekOfYear ?? 0
                let totalWeek = weeksSinceStart + 1
                let blockInfo = scheduleManager.getBlockForWeek(totalWeek)
                let daysToDeload = calendar.dateComponents([.day], from: day.date, to: block.endDate).day
                
                ProgramContextBanner(
                    blockType: block.type,
                    weekNumber: blockInfo.weekInBlock,
                    totalWeeks: block.type.duration,
                    daysToDeload: daysToDeload
                )
            }
            
            // Collapsible content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let structuredWorkout = day.structuredWorkout {
                        StructuredWorkoutView(workout: structuredWorkout)
                    } else if !day.hasWorkout {
                        NoWorkoutView(context: determineEmptyContext())
                    }

                    Divider()
                        .padding(.vertical, 8)

                    ResultsSection(day: day, scheduleManager: scheduleManager)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
    
    private func determineEmptyContext() -> NoWorkoutView.EmptyContext {
        let isPast = day.date < Date.current
        if isPast {
            return .pastUnfilled
        } else {
            return .notPlanned
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Structured Workout Views

struct StructuredWorkoutView: View {
    let workout: StructuredWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Compact summary header
            WorkoutSummaryView(
                title: workout.title,
                duration: workout.totalDuration,
                rpe: extractRPE(from: workout.notes),
                modality: extractModality(from: workout.notes)
            )
            
            // Vertical stack of all exercises
            ForEach(workout.exercises, id: \.id) { exercise in
                ExerciseCard(exercise: exercise)
            }
            
            // Coaching notes at bottom
            if let notes = workout.notes {
                CoachingNotesView(notes: notes)
            }
        }
    }
    
    // Helper to extract RPE from notes
    private func extractRPE(from notes: String?) -> String? {
        guard let notes = notes else { return nil }
        
        // Look for RPE pattern like "RPE 3-4" or "RPE 6–7"
        let rpePattern = #"RPE\s*(\d+[-–]\d+|\d+)"#
        if let range = notes.range(of: rpePattern, options: .regularExpression) {
            return String(notes[range])
        }
        return nil
    }
    
    // Helper to extract modality from notes or workout title
    private func extractModality(from notes: String?) -> String? {
        guard let notes = notes else { return nil }
        
        let lower = notes.lowercased()
        if lower.contains("bike") || lower.contains("spin") || lower.contains("cycling") {
            return "Bike"
        } else if lower.contains("run") {
            return "Running"
        } else if lower.contains("swim") {
            return "Swimming"
        } else if lower.contains("erg") || lower.contains("row") {
            return "Rowing"
        } else if lower.contains("strength") {
            return "Strength"
        } else if lower.contains("yoga") {
            return "Yoga"
        } else if lower.contains("mobility") {
            return "Mobility"
        }
        return nil
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise header
            HStack {
                if let name = exercise.name {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text(exercise.kind.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                if let focus = exercise.focus {
                    Text(focus)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray4))
                        .cornerRadius(12)
                }
            }
            
            // Exercise detail based on type
            switch exercise.detail {
            case .cardio(let detail):
                CardioExerciseView(detail: detail)
            case .strength(let detail):
                StrengthExerciseView(detail: detail)
            case .mobility(let detail):
                MobilityExerciseView(detail: detail)
            case .yoga(let detail):
                YogaExerciseView(detail: detail)
            case .generic(let detail):
                GenericExerciseView(detail: detail)
            }
        }
        .padding(16)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
}

struct CardioExerciseView: View {
    let detail: CardioDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Summary chips
            HStack {
                if let modality = detail.modality {
                    Chip(text: modality.capitalized, color: .blue)
                }
                
                if let total = detail.effectiveTotal {
                    if let duration = total.durationMinutes {
                        Chip(text: "\(duration) min", color: .green)
                    }
                    if let distance = total.distanceMeters {
                        let km = Double(distance) / 1000.0
                        Chip(text: String(format: "%.1f km", km), color: .green)
                    }
                }
            }
            
            // Segments/intervals
            if let segments = detail.segments, !segments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intervals")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        IntervalRow(segment: segment)
                    }
                }
            }
        }
    }
}

struct IntervalRow: View {
    let segment: CardioSegment
    
    var body: some View {
        HStack {
            if let repeatCount = segment.repeat, repeatCount > 1 {
                Text("\(repeatCount)×")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 30, alignment: .leading)
            }
            
            if let work = segment.work {
                VStack(alignment: .leading, spacing: 2) {
                    if let duration = work.durationMinutes {
                        Text("\(duration) min work")
                            .font(.caption)
                    } else if let distance = work.distanceMeters {
                        Text("\(distance)m work")
                            .font(.caption)
                    }
                    
                    if let target = work.target {
                        HStack {
                            if let hrZone = target.hrZone {
                                Text(hrZone)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            if let pace = target.pace {
                                Text(pace)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if let cadence = target.cadence {
                                Text("\(cadence) rpm")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                }
            }
            
            if let rest = segment.rest {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let duration = rest.durationMinutes {
                        Text("\(duration) min rest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let distance = rest.distanceMeters {
                        Text("\(distance)m rest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct StrengthExerciseView: View {
    let detail: StrengthDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let movement = detail.movement {
                Text(movement.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let sets = detail.sets, !sets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sets")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                        StrengthSetRow(set: set)
                    }
                }
            }
        }
    }
}

struct StrengthSetRow: View {
    let set: StrengthSet
    
    var body: some View {
        HStack {
            Text("Set \(set.set)")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 40, alignment: .leading)
            
            if let reps = set.reps {
                Text("\(reps.displayValue) reps")
                    .font(.caption)
                    .frame(width: 50, alignment: .leading)
            }
            
            if let weight = set.weight {
                Text(weight)
                    .font(.caption)
                    .frame(width: 50, alignment: .leading)
            }
            
            if let rir = set.rir {
                Text("RIR \(rir)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            if let tempo = set.tempo {
                Text(tempo)
                    .font(.caption2)
                    .foregroundColor(.purple)
            }
            
            Spacer()
            
            if let rest = set.restSeconds {
                Text("\(rest)s rest")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MobilityExerciseView: View {
    let detail: MobilityDetail
    
    var body: some View {
        if let blocks = detail.blocks, !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Movements")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    MobilityBlockRow(block: block)
                }
            }
        }
    }
}

struct MobilityBlockRow: View {
    let block: MobilityBlock
    
    var body: some View {
        HStack {
            Text(block.name)
                .font(.caption)
            
            Spacer()
            
            HStack(spacing: 8) {
                if let hold = block.holdSeconds {
                    Text("\(hold)s")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                if let sides = block.sides, sides > 1 {
                    Text("each side")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let reps = block.reps {
                    Text("\(reps) reps")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct YogaExerciseView: View {
    let detail: YogaDetail
    
    var body: some View {
        if let blocks = detail.blocks, !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sequence")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    YogaBlockRow(block: block)
                }
            }
        }
    }
}

struct YogaBlockRow: View {
    let block: YogaBlock
    
    var body: some View {
        HStack {
            Text(block.name)
                .font(.caption)
            
            Spacer()
            
            if let duration = block.durationMinutes {
                Text("\(duration) min")
                    .font(.caption2)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GenericExerciseView: View {
    let detail: GenericDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let items = detail.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(item)
                            .font(.caption)
                    }
                }
            }
            
            if let notes = detail.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct NoWorkoutView: View {
    let context: EmptyContext
    
    enum EmptyContext {
        case restDay
        case notPlanned
        case pastUnfilled
        
        var icon: String {
            switch self {
            case .restDay: return "bed.double.fill"
            case .notPlanned: return "calendar.badge.plus"
            case .pastUnfilled: return "calendar.badge.exclamationmark"
            }
        }
        
        var message: String {
            switch self {
            case .restDay: return "Rest day - Recovery is progress 💪"
            case .notPlanned: return "Ask your coach to plan this workout"
            case .pastUnfilled: return "This workout was skipped"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: context.icon)
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text(context.message)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}

struct Chip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(12)
    }
}

// MARK: - Preview Support

#Preview {
    let sampleWorkout = StructuredWorkout(
        title: "Sample Workout",
        summary: "Cardio + Strength",
        durationMinutes: 60,
        notes: "Stay hydrated",
        exercises: [
            Exercise(
                kind: "cardioBike",
                name: "Bike intervals",
                focus: "Zone 4",
                equipment: nil,
                tags: nil,
                detail: .cardio(CardioDetail(
                    modality: "bike",
                    total: CardioTotal(durationMinutes: 30, distanceMeters: nil),
                    segments: [
                        CardioSegment(
                            repeat: 4,
                            work: CardioInterval(
                                durationMinutes: 3,
                                distanceMeters: nil,
                                target: CardioTarget(hrZone: "Z4", pace: nil, power: nil, rpe: nil, cadence: "90-95")
                            ),
                            rest: CardioInterval(
                                durationMinutes: 2,
                                distanceMeters: nil,
                                target: CardioTarget(hrZone: "Z2", pace: nil, power: nil, rpe: nil, cadence: "85")
                            )
                        )
                    ]
                ))
            ),
            Exercise(
                kind: "strength",
                name: "Squats",
                focus: nil,
                equipment: "barbell",
                tags: nil,
                detail: .strength(StrengthDetail(
                    movement: "back_squat",
                    sets: [
                        StrengthSet(set: 1, reps: .integer(8), weight: "60kg", rir: 2, tempo: "2-0-2", restSeconds: 120),
                        StrengthSet(set: 2, reps: .integer(8), weight: "60kg", rir: 2, tempo: "2-0-2", restSeconds: 120)
                    ],
                    superset: nil
                ))
            )
        ]
    )
    
    let sampleDay = WorkoutDay(date: Date(), blockType: .aerobicCapacity)
    
    VStack {
        StructuredWorkoutView(workout: sampleWorkout)
        Spacer()
    }
    .padding()
}

// MARK: - Results Section (Per-Day Logged Sets)
struct ResultsSection: View {
    let day: WorkoutDay
    @ObservedObject var scheduleManager: TrainingScheduleManager
    @ObservedObject private var resultsManager = WorkoutResultsManager.shared
    @State private var results: [WorkoutSetResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Results")
                    .font(Font.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary.opacity(0.6))
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.6))
                        .padding(4)
                        .background(Circle().fill(Color(.systemGray5)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh results")
            }

            if sortedResults.isEmpty {
                Text("No results logged yet.")
                    .font(Font.subheadline)
                    .foregroundColor(.primary.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedResults.indices, id: \.self) { idx in
                        let r = sortedResults[idx]
                        Text(formattedLine(for: r))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray5))
        .cornerRadius(8)
        .onAppear { refresh() }
        .onChange(of: day.id) { _, _ in refresh() }
    }

    private var sortedResults: [WorkoutSetResult] {
        results.sorted { $0.timestamp < $1.timestamp }
    }

    private func formattedLine(for r: WorkoutSetResult) -> String {
        var line = "• \(r.exerciseName)"
        
        // Detect modality based on which fields are present
        let hasStrengthFields = r.setNumber != nil || r.reps != nil || r.loadLb != nil || r.rir != nil
        let hasCardioFields = r.interval != nil || r.time != nil || r.distance != nil || r.pace != nil || r.spm != nil || r.hr != nil || r.power != nil || r.cadence != nil
        
        // Format based on modality
        if hasCardioFields {
            // Cardio/Interval formatting
            if let interval = r.interval { line += " — Interval \(interval)" }
            
            var metrics: [String] = []
            if let time = r.time { metrics.append(time) }
            if let distance = r.distance { metrics.append(distance) }
            if let pace = r.pace { metrics.append("@ \(pace)") }
            if !metrics.isEmpty { line += ": " + metrics.joined(separator: ", ") }
            
            var details: [String] = []
            if let spm = r.spm { details.append("\(spm) spm") }
            if let hr = r.hr { details.append("\(hr) bpm") }
            if let power = r.power { details.append("\(power)W") }
            if let cadence = r.cadence { details.append("\(cadence) rpm") }
            if !details.isEmpty { line += " (" + details.joined(separator: ", ") + ")" }
            
        } else if hasStrengthFields {
            // Strength training formatting
            if let set = r.setNumber { line += " — Set \(set)" }
            
            var metrics: [String] = []
            if let reps = r.reps { metrics.append("\(reps) reps") }
            if let w = weightText(r) { metrics.append(w) }
            if !metrics.isEmpty { line += ": " + metrics.joined(separator: " × ") }
            
            var suffix: [String] = []
            if let rir = r.rir { suffix.append("RIR \(rir)") }
            if let rpe = r.rpe { suffix.append("RPE \(rpe)") }  // Deprecated but still display if present
            if !suffix.isEmpty { line += " (" + suffix.joined(separator: ", ") + ")" }
            
        } else {
            // Mobility/generic (only has time or notes)
            if let time = r.time { line += ": \(time)" }
        }
        
        // Add notes if present (universal)
        if let notes = r.notes, !notes.isEmpty {
            line += " — \(notes)"
        }
        
        return line
    }

    private func weightText(_ r: WorkoutSetResult) -> String? {
        if let lb = r.loadLb, !lb.isEmpty {
            if lb.lowercased().contains("lb") || lb.lowercased().contains("kg") { return lb }
            return "\(lb) lb"
        }
        // Backward compatibility: still display loadKg if present
        if let kg = r.loadKg, !kg.isEmpty {
            if kg.lowercased().contains("kg") || kg.lowercased().contains("lb") { return kg }
            return "\(kg) kg"
        }
        return nil
    }

    private func refresh() {
        results = resultsManager.loadSetResults(for: day.date)
    }
}