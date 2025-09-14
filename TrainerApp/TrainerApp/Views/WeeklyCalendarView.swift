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
            
            // Use coach-selected icon or show "no workout" indicator
            Image(systemName: workoutIcon)
                .font(.system(size: 20))
                .foregroundColor(workoutIconColor)
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
            HStack {
                Image(systemName: day.displayIcon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.dayOfWeek.name)")
                        .font(.headline)
                    Text(dateFormatter.string(from: day.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let summary = day.displaySummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    if let structuredWorkout = day.structuredWorkout {
                        StructuredWorkoutView(workout: structuredWorkout)
                    } else if !day.hasWorkout {
                        NoWorkoutView()
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

// MARK: - Structured Workout Views

struct StructuredWorkoutView: View {
    let workout: StructuredWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Workout header
            if let title = workout.title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let duration = workout.totalDuration {
                        Text("\(duration) minutes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let notes = workout.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBlue).opacity(0.1))
                .cornerRadius(8)
            }
            
            // Exercises list
            ForEach(workout.exercises) { exercise in
                ExerciseCard(exercise: exercise)
            }
        }
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
        .padding()
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
    var body: some View {
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