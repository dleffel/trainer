import Foundation

// MARK: - WorkoutTemplate

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
    
    init(title: String, summary: String, sessionType: WorkoutSessionType, modalityPrimary: String, modalitySecondary: String? = nil, focus: String, durationMinutes: Int? = nil, intensityZone: String? = nil, icon: String, notes: String? = nil) {
        self.title = title
        self.summary = summary
        self.sessionType = sessionType
        self.modalityPrimary = modalityPrimary
        self.modalitySecondary = modalitySecondary
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.intensityZone = intensityZone
        self.icon = icon
        self.notes = notes
    }
}

// MARK: - WorkoutSessionType

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

// MARK: - TrainingBlockTemplate

/// Defines the weekly workout template for a specific training block type
struct TrainingBlockTemplate: Codable {
    let blockType: BlockType
    let weeklyTemplate: [DayOfWeek: WorkoutTemplate]
    
    init(blockType: BlockType, weeklyTemplate: [DayOfWeek: WorkoutTemplate]) {
        self.blockType = blockType
        self.weeklyTemplate = weeklyTemplate
    }
    
    /// Get the workout template for a specific day
    func templateForDay(_ day: DayOfWeek) -> WorkoutTemplate? {
        return weeklyTemplate[day]
    }
}

// MARK: - Predefined Templates

extension TrainingBlockTemplate {
    
    /// Static templates for all training block types
    static let templates: [BlockType: TrainingBlockTemplate] = [
        .hypertrophyStrength: hypertrophyStrengthTemplate,
        .deload: deloadTemplate,
        .aerobicCapacity: aerobicCapacityTemplate
    ]
    
    /// Get template for a specific block type
    static func template(for blockType: BlockType) -> TrainingBlockTemplate? {
        return templates[blockType]
    }
    
    // MARK: - Hypertrophy-Strength Block Template (10 weeks)
    
    private static let hypertrophyStrengthTemplate = TrainingBlockTemplate(
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
    )
    
    // MARK: - Deload Block Template (1 week, -30% volume)
    
    private static let deloadTemplate = TrainingBlockTemplate(
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
    )
    
    // MARK: - Aerobic-Capacity Block Template (8 weeks)
    
    private static let aerobicCapacityTemplate = TrainingBlockTemplate(
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
}