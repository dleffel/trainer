import Foundation

/// Categorizes the primary type of workout session
enum WorkoutSessionType: String, CaseIterable, Codable {
    case strength = "Strength"
    case cardio = "Cardio"
    case mobility = "Mobility"
    case rest = "Rest"
    case mixed = "Mixed"
    
    var defaultIcon: String {
        switch self {
        case .strength:
            return "figure.strengthtraining.traditional"
        case .cardio:
            return "figure.mixed.cardio"
        case .mobility:
            return "figure.flexibility"
        case .rest:
            return "bed.double.fill"
        case .mixed:
            return "figure.mixed.cardio"
        }
    }
}

/// Represents a template for a specific workout type within a training block
struct WorkoutTemplate: Codable {
    let title: String
    let summary: String
    let sessionType: WorkoutSessionType
    let modalityPrimary: String
    let modalitySecondary: String?
    let focus: String
    let durationMinutes: Int?
    let intensityZone: String?
    let icon: String
    let notes: String?
}

/// Defines the weekly workout template for a specific training block type
struct TrainingBlockTemplate: Codable {
    let blockType: BlockType
    let weeklyTemplate: [DayOfWeek: WorkoutTemplate]
    
    /// Get the workout template for a specific day
    func templateForDay(_ day: DayOfWeek) -> WorkoutTemplate? {
        return weeklyTemplate[day]
    }
    
    /// Get template for a specific block type
    static func template(for blockType: BlockType) -> TrainingBlockTemplate? {
        return templates[blockType]
    }
    
    /// Static templates for all training block types
    static let templates: [BlockType: TrainingBlockTemplate] = [
        .hypertrophyStrength: TrainingBlockTemplate(
            blockType: .hypertrophyStrength,
            weeklyTemplate: [
                .monday: WorkoutTemplate(
                    title: "Rest Day",
                    summary: "Mobility + core (15–25′)",
                    sessionType: .mobility,
                    modalityPrimary: "mobility",
                    modalitySecondary: nil,
                    focus: "Tissue quality, hips/thoracic",
                    durationMinutes: 20,
                    intensityZone: "Recovery",
                    icon: "figure.flexibility",
                    notes: "Focus on hip and thoracic spine mobility"
                ),
                .tuesday: WorkoutTemplate(
                    title: "Strength - Lower + Z2",
                    summary: "Strength – Lower (squat/hinge) → 30–40′ Z2 bike or erg",
                    sessionType: .mixed,
                    modalityPrimary: "strength",
                    modalitySecondary: "bike",
                    focus: "Hypertrophy (legs); easy aerobic",
                    durationMinutes: 90,
                    intensityZone: "Strength + Z2",
                    icon: "figure.strengthtraining.traditional",
                    notes: "Squat/hinge movements followed by easy aerobic work"
                ),
                .wednesday: WorkoutTemplate(
                    title: "RowErg Z2 + Technique",
                    summary: "40–60′ RowErg Z2 @18–20 spm + 10′ technique drills",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Technique, capillary base",
                    durationMinutes: 60,
                    intensityZone: "Z2",
                    icon: "figure.rower",
                    notes: "Focus on stroke rate consistency and technique drills"
                ),
                .thursday: WorkoutTemplate(
                    title: "Strength - Upper + Z2",
                    summary: "Strength – Upper (press/pull) → 30–40′ Z2 spin",
                    sessionType: .mixed,
                    modalityPrimary: "strength",
                    modalitySecondary: "bike",
                    focus: "Hypertrophy (upper); easy aerobic",
                    durationMinutes: 90,
                    intensityZone: "Strength + Z2",
                    icon: "figure.strengthtraining.traditional",
                    notes: "Press/pull movements followed by easy spin"
                ),
                .friday: WorkoutTemplate(
                    title: "Long RowErg Z2",
                    summary: "60–90′ RowErg Z2 (occasional 10×10″ power strokes, full recovery)",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Aerobic base + stroke power touches",
                    durationMinutes: 75,
                    intensityZone: "Z2",
                    icon: "figure.rower",
                    notes: "Steady state with occasional power stroke touches"
                ),
                .saturday: WorkoutTemplate(
                    title: "Strength - Full Body + Optional Spin",
                    summary: "Strength – Full Body/Posterior (RDL/row/pull-ups) ± PM 30–45′ spin Z1–Z2",
                    sessionType: .mixed,
                    modalityPrimary: "strength",
                    modalitySecondary: "bike",
                    focus: "Third hypertrophy hit; optional flush",
                    durationMinutes: 90,
                    intensityZone: "Strength + Z1-Z2",
                    icon: "figure.strengthtraining.traditional",
                    notes: "Full body emphasis on posterior chain"
                ),
                .sunday: WorkoutTemplate(
                    title: "Long Aerobic",
                    summary: "75–120′ RowErg Z2 or 60–90′ run/walk-run (incline treadmill ok)",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: "run",
                    focus: "Long aerobic steady",
                    durationMinutes: 90,
                    intensityZone: "Z2",
                    icon: "figure.rower",
                    notes: "Choose modality based on preference and back comfort"
                )
            ]
        ),
        .deload: TrainingBlockTemplate(
            blockType: .deload,
            weeklyTemplate: [
                .monday: WorkoutTemplate(
                    title: "Recovery",
                    summary: "Mobility + breathing 15–20′",
                    sessionType: .mobility,
                    modalityPrimary: "mobility",
                    modalitySecondary: nil,
                    focus: "Recovery",
                    durationMinutes: 18,
                    intensityZone: "Recovery",
                    icon: "figure.flexibility",
                    notes: "Focus on breath work and gentle movement"
                ),
                .tuesday: WorkoutTemplate(
                    title: "Easy Flush",
                    summary: "30–40′ spin/erg Z1–low Z2",
                    sessionType: .cardio,
                    modalityPrimary: "bike",
                    modalitySecondary: "row",
                    focus: "Flush",
                    durationMinutes: 35,
                    intensityZone: "Z1-low Z2",
                    icon: "bicycle",
                    notes: "Very easy effort, focus on movement quality"
                ),
                .wednesday: WorkoutTemplate(
                    title: "Light Strength",
                    summary: "Light Full-Body Strength (machines/DBs; 2×8–12, RIR 3–4)",
                    sessionType: .strength,
                    modalityPrimary: "strength",
                    modalitySecondary: nil,
                    focus: "Movement maintenance",
                    durationMinutes: 45,
                    intensityZone: "Light",
                    icon: "figure.strengthtraining.traditional",
                    notes: "Focus on movement patterns, not load"
                ),
                .thursday: WorkoutTemplate(
                    title: "Technique Focus",
                    summary: "30–45′ erg technique (pick drills, pauses)",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Skill",
                    durationMinutes: 38,
                    intensityZone: "Z1",
                    icon: "figure.rower",
                    notes: "Emphasis on stroke mechanics and drills"
                ),
                .friday: WorkoutTemplate(
                    title: "Base Maintenance",
                    summary: "40–60′ spin/erg Z2",
                    sessionType: .cardio,
                    modalityPrimary: "bike",
                    modalitySecondary: "row",
                    focus: "Base",
                    durationMinutes: 50,
                    intensityZone: "Z2",
                    icon: "bicycle",
                    notes: "Comfortable aerobic effort"
                ),
                .saturday: WorkoutTemplate(
                    title: "Easy Movement",
                    summary: "30–40′ walk/run or spin + mobility",
                    sessionType: .mixed,
                    modalityPrimary: "run",
                    modalitySecondary: "bike",
                    focus: "Easy",
                    durationMinutes: 35,
                    intensityZone: "Z1",
                    icon: "figure.run",
                    notes: "Very gentle movement plus stretching"
                ),
                .sunday: WorkoutTemplate(
                    title: "Absorb",
                    summary: "Off or 30–40′ Z1 + mobility",
                    sessionType: .rest,
                    modalityPrimary: "mobility",
                    modalitySecondary: nil,
                    focus: "Absorb",
                    durationMinutes: 35,
                    intensityZone: "Z1 or Rest",
                    icon: "bed.double.fill",
                    notes: "Complete rest or very gentle movement"
                )
            ]
        ),
        .aerobicCapacity: TrainingBlockTemplate(
            blockType: .aerobicCapacity,
            weeklyTemplate: [
                .monday: WorkoutTemplate(
                    title: "Prep",
                    summary: "Mobility + core 15–20′",
                    sessionType: .mobility,
                    modalityPrimary: "mobility",
                    modalitySecondary: nil,
                    focus: "Prep tissues",
                    durationMinutes: 18,
                    intensityZone: "Recovery",
                    icon: "figure.flexibility",
                    notes: "Prepare body for higher intensity week"
                ),
                .tuesday: WorkoutTemplate(
                    title: "Base + Power Strides",
                    summary: "60–90′ RowErg Z2 with 8–12×20″ @ Z3/UT1, 100″ easy",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Aerobic base + aerobic power strides",
                    durationMinutes: 75,
                    intensityZone: "Z2 + Z3/UT1",
                    icon: "figure.rower",
                    notes: "Steady base with short power touches"
                ),
                .wednesday: WorkoutTemplate(
                    title: "Strength Maintenance",
                    summary: "Strength – Full Body (Maintenance) 45–60′ (2–3×5–8 main, RIR 2) ± 15–20′ easy spin",
                    sessionType: .mixed,
                    modalityPrimary: "strength",
                    modalitySecondary: "bike",
                    focus: "Strength maintenance",
                    durationMinutes: 75,
                    intensityZone: "Maintenance + Z1",
                    icon: "figure.strengthtraining.traditional",
                    notes: "Maintain strength with reduced volume"
                ),
                .thursday: WorkoutTemplate(
                    title: "Threshold",
                    summary: "Threshold on erg (e.g., 3×12′ @ AT / 10k effort, 3′ easy) or 35–50′ steady tempo",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Raise LT/AT",
                    durationMinutes: 60,
                    intensityZone: "AT/Threshold",
                    icon: "figure.rower",
                    notes: "Lactate threshold focused intervals"
                ),
                .friday: WorkoutTemplate(
                    title: "Volume",
                    summary: "75–120′ RowErg Z2 @ 18–20 spm (no surges)",
                    sessionType: .cardio,
                    modalityPrimary: "row",
                    modalitySecondary: nil,
                    focus: "Volume",
                    durationMinutes: 95,
                    intensityZone: "Z2",
                    icon: "figure.rower",
                    notes: "Steady volume work at controlled stroke rate"
                ),
                .saturday: WorkoutTemplate(
                    title: "VO₂ / High-UT1",
                    summary: "VO₂ / High-UT1 on erg (e.g., 5–6×4′ @ ~5k pace, 3′ easy) ± PM 30–45′ Z1 spin",
                    sessionType: .mixed,
                    modalityPrimary: "row",
                    modalitySecondary: "bike",
                    focus: "Top-end aerobic",
                    durationMinutes: 90,
                    intensityZone: "VO₂/High-UT1 + Z1",
                    icon: "figure.rower",
                    notes: "High intensity aerobic power development"
                ),
                .sunday: WorkoutTemplate(
                    title: "Long Cross-Training",
                    summary: "90–150′ bike Z2 or 75–120′ erg Z2; alternate modality weekly",
                    sessionType: .cardio,
                    modalityPrimary: "bike",
                    modalitySecondary: "row",
                    focus: "Long aerobic, joint-friendly",
                    durationMinutes: 120,
                    intensityZone: "Z2",
                    icon: "bicycle",
                    notes: "Alternate between bike and erg weekly for joint health"
                )
            ]
        )
    ]
}

/// Days of the week for workout scheduling
enum DayOfWeek: Int, CaseIterable, Codable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7
    
    var name: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
    
    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
    
    
}

/// Workout type icons for coach selection
enum WorkoutType: String, CaseIterable {
    case rest = "bed.double.fill"
    case rowing = "figure.rower"
    case cycling = "bicycle"
    case running = "figure.run"
    case strength = "figure.strengthtraining.traditional"
    case yoga = "figure.yoga"
    case swimming = "figure.pool.swim"
    case crossTraining = "figure.mixed.cardio"
    case recovery = "heart.fill"
    case testing = "chart.line.uptrend.xyaxis"
    case noWorkout = "calendar.badge.exclamationmark"
    
    var icon: String {
        return self.rawValue
    }
}

/// Represents a single day in the training calendar
struct WorkoutDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let dayOfWeek: DayOfWeek
    let blockType: BlockType
    var plannedWorkout: String?  // Legacy field - kept for backward compatibility, read-only
    var isCoachPlanned: Bool = false  // Track if coach-generated vs template
    var workoutIcon: String?  // Coach-selected icon (SF Symbol name)
    
    // NEW: Structured workout data
    var structuredWorkout: StructuredWorkout?
    
    // NEW: Template tracking
    var isTemplateGenerated: Bool = false  // Track if generated from template
    var templateType: WorkoutSessionType?  // Type of template used
    
    init(date: Date, blockType: BlockType, plannedWorkout: String? = nil) {
        self.date = date
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Convert from Sunday = 1 to Monday = 1
        self.dayOfWeek = DayOfWeek(rawValue: weekday == 1 ? 7 : weekday - 1) ?? .monday
        self.blockType = blockType
        
        if let workout = plannedWorkout {
            // Use provided workout (legacy path)
            self.plannedWorkout = workout
            self.isCoachPlanned = true
        } else {
            // Leave blank for coach to fill in later
            self.plannedWorkout = nil
            self.isCoachPlanned = false
        }
    }
    
    /// Create a WorkoutDay with template-generated content
    static func withTemplate(date: Date, blockType: BlockType, template: WorkoutTemplate) -> WorkoutDay {
        var workoutDay = WorkoutDay(date: date, blockType: blockType)
        workoutDay.applyTemplate(template)
        return workoutDay
    }
    
    /// Apply a workout template to this day
    mutating func applyTemplate(_ template: WorkoutTemplate) {
        self.isTemplateGenerated = true
        self.templateType = template.sessionType
        self.workoutIcon = template.icon
        self.isCoachPlanned = false // Template-generated, not coach-planned
        
        // Create a skeleton StructuredWorkout from the template
        self.structuredWorkout = createStructuredWorkoutFromTemplate(template)
    }
    
    /// Create a StructuredWorkout from a template (placeholder for coach to customize)
    private func createStructuredWorkoutFromTemplate(_ template: WorkoutTemplate) -> StructuredWorkout {
        let placeholderExercise = Exercise(
            kind: template.modalityPrimary,
            name: template.summary,
            focus: template.focus,
            equipment: nil,
            tags: nil,
            detail: .generic(GenericDetail(
                items: ["Template: \(template.focus)"],
                notes: template.notes
            ))
        )
        
        return StructuredWorkout(
            title: template.title,
            summary: template.summary,
            durationMinutes: template.durationMinutes,
            notes: template.notes,
            exercises: [placeholderExercise]
        )
    }
    
    /// Check if this day has any workout content (structured, legacy, or template)
    var hasWorkout: Bool {
        let result = structuredWorkout != nil || plannedWorkout != nil || isTemplateGenerated
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        print("🔍 hasWorkout DEBUG: \(dayOfWeek.name) \(formatter.string(from: date)) - plannedWorkout: \(plannedWorkout != nil), structuredWorkout: \(structuredWorkout != nil), isTemplateGenerated: \(isTemplateGenerated), hasWorkout: \(result)")
        return result
    }
    
    /// Get the display icon for this workout day
    var displayIcon: String {
        // Priority 1: Coach-selected icon
        if let workoutIcon = workoutIcon {
            return workoutIcon
        }
        
        // Priority 2: Derive from structured workout
        if let structured = structuredWorkout {
            return structured.derivedIcon
        }
        
        // Priority 3: Template type default icon
        if isTemplateGenerated, let templateType = templateType {
            return templateType.defaultIcon
        }
        
        // Priority 4: No workout indicator
        return WorkoutType.noWorkout.icon
    }
    
    /// Get a summary for display (structured takes priority, then legacy, then template)
    var displaySummary: String? {
        if let structured = structuredWorkout {
            return structured.displaySummary
        }
        
        if let planned = plannedWorkout {
            return planned
        }
        
        if isTemplateGenerated, let templateType = templateType {
            return "Template: \(templateType.rawValue)"
        }
        
        return nil
    }
    
    /// Check if this is a coach-customized workout (vs template or blank)
    var isCoachCustomized: Bool {
        return isCoachPlanned || (structuredWorkout != nil && !isTemplateGenerated)
    }
    
    /// Get the workout status for UI display
    var workoutStatus: WorkoutStatus {
        if isCoachCustomized {
            return .coachPlanned
        } else if isTemplateGenerated {
            return .templateGenerated
        } else {
            return .blank
        }
    }
}

/// Represents the status of a workout day for UI purposes
enum WorkoutStatus: String, CaseIterable {
    case blank = "Blank"
    case templateGenerated = "Template"
    case coachPlanned = "Coach Planned"
    
    var icon: String {
        switch self {
        case .blank:
            return "calendar.badge.exclamationmark"
        case .templateGenerated:
            return "doc.text"
        case .coachPlanned:
            return "checkmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .blank:
            return "gray"
        case .templateGenerated:
            return "blue"
        case .coachPlanned:
            return "green"
        }
    }
}
