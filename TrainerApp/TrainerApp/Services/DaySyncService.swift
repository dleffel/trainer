import Foundation
import Combine

/// Orchestrates syncing a single day's workout data to the Organizer Exercise API
/// Coordinates mapping, deletion, and creation of all exercise data
class DaySyncService: ObservableObject {
    static let shared = DaySyncService()
    
    private let apiService = ExerciseAPIService.shared
    private let mapper = WorkoutToAPIMapper.shared
    private let resultsManager = WorkoutResultsManager.shared
    
    // MARK: - Published State
    
    /// Current sync status for UI binding
    @Published private(set) var status: SyncStatus = .idle
    
    /// Last sync error if any
    @Published private(set) var lastError: Error?
    
    private init() {}
    
    // MARK: - Sync Status
    
    enum SyncStatus: Equatable {
        case idle
        case mapping
        case deletingExisting
        case creatingEntry
        case syncingStrength(Int, Int)  // current, total
        case syncingCardio(Int, Int)    // current, total
        case syncingYoga
        case complete
        case failed
        
        var description: String {
            switch self {
            case .idle:
                return "Ready to sync"
            case .mapping:
                return "Preparing data..."
            case .deletingExisting:
                return "Clearing old data..."
            case .creatingEntry:
                return "Creating entry..."
            case .syncingStrength(let current, let total):
                return "Syncing strength \(current)/\(total)..."
            case .syncingCardio(let current, let total):
                return "Syncing cardio \(current)/\(total)..."
            case .syncingYoga:
                return "Syncing mobility..."
            case .complete:
                return "Sync complete!"
            case .failed:
                return "Sync failed"
            }
        }
        
        var isInProgress: Bool {
            switch self {
            case .idle, .complete, .failed:
                return false
            default:
                return true
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Sync a workout day to the Organizer API
    /// - Parameter workoutDay: The workout day to sync
    /// - Throws: Various errors if sync fails
    func syncDay(_ workoutDay: WorkoutDay) async throws {
        let date = workoutDay.date
        
        print("🔄 DaySyncService: Starting sync for \(formatDateForLog(date))")
        
        // Reset state
        await updateStatus(.idle)
        lastError = nil
        
        do {
            // Step 1: Load results for this day
            print("📊 Step 1: Loading logged results...")
            let results = resultsManager.loadSetResults(for: date)
            print("   Loaded \(results.count) logged results for the day")
            
            // Step 2: Map data using LLM
            print("🤖 Step 2: Mapping data via LLM...")
            await updateStatus(.mapping)
            let mappedData: MappedDayData
            do {
                mappedData = try await mapper.mapWorkoutToAPI(
                    workoutDay: workoutDay,
                    results: results
                )
                print("   ✅ LLM mapping complete")
                print("   Mapped: \(mappedData.strengthExercises?.count ?? 0) strength, \(mappedData.cardioWorkouts?.count ?? 0) cardio, yoga: \(mappedData.yogaMobility != nil)")
            } catch {
                print("   ❌ LLM mapping failed: \(error)")
                throw error
            }
            
            // Step 3: Delete existing entry (if any) - ignore 404
            print("🗑️ Step 3: Deleting existing entry...")
            await updateStatus(.deletingExisting)
            do {
                try await apiService.deleteEntry(for: date)
                print("   ✅ Deleted existing entry")
            } catch ExerciseAPIError.notFound {
                print("   ℹ️ No existing entry to delete (404)")
            } catch ExerciseAPIError.httpError(let code) where code == 405 {
                // 405 on DELETE might mean the entry doesn't exist or endpoint issue
                print("   ⚠️ DELETE returned 405 - continuing anyway")
            }
            
            // Step 4: Create new entry
            print("📝 Step 4: Creating entry...")
            await updateStatus(.creatingEntry)
            do {
                let _ = try await apiService.createEntry(
                    for: date,
                    primaryModality: mappedData.entry.primaryModality,
                    notes: mappedData.entry.dayNotes
                )
                print("   ✅ Created entry with modality: \(mappedData.entry.primaryModality ?? "none")")
            } catch {
                print("   ❌ Failed to create entry: \(error)")
                throw error
            }
            
            // Step 5: Sync strength exercises
            if let strengthExercises = mappedData.strengthExercises, !strengthExercises.isEmpty {
                print("💪 Step 5: Syncing \(strengthExercises.count) strength exercises...")
                try await syncStrengthExercises(strengthExercises, date: date)
            } else {
                print("💪 Step 5: No strength exercises to sync")
            }
            
            // Step 6: Sync cardio workouts
            if let cardioWorkouts = mappedData.cardioWorkouts, !cardioWorkouts.isEmpty {
                print("🏃 Step 6: Syncing \(cardioWorkouts.count) cardio workouts...")
                try await syncCardioWorkouts(cardioWorkouts, date: date)
            } else {
                print("🏃 Step 6: No cardio workouts to sync")
            }
            
            // Step 7: Sync yoga/mobility
            if let yoga = mappedData.yogaMobility {
                print("🧘 Step 7: Syncing yoga/mobility...")
                try await syncYogaMobility(yoga, date: date)
            } else {
                print("🧘 Step 7: No yoga/mobility to sync")
            }
            
            await updateStatus(.complete)
            print("🎉 DaySyncService: Sync complete for \(formatDateForLog(date))")
            
        } catch {
            print("❌ DaySyncService: Sync failed at status '\(status.description)'")
            print("   Error: \(error)")
            if let apiError = error as? ExerciseAPIError {
                print("   API Error Type: \(apiError)")
            }
            await MainActor.run {
                self.lastError = error
                self.status = .failed
            }
            throw error
        }
    }
    
    /// Reset sync state to idle
    func reset() {
        Task { @MainActor in
            status = .idle
            lastError = nil
        }
    }
    
    // MARK: - Private Sync Methods
    
    private func syncStrengthExercises(_ exercises: [MappedStrengthExercise], date: Date) async throws {
        print("💪 Syncing \(exercises.count) strength exercises...")
        
        for (index, exercise) in exercises.enumerated() {
            await updateStatus(.syncingStrength(index + 1, exercises.count))
            
            // Create the exercise
            let createdExercise = try await apiService.addStrengthExercise(
                date: date,
                exercise: StrengthExerciseRequest(
                    name: exercise.name,
                    notes: exercise.notes,
                    coachNotes: exercise.coachNotes,
                    displayOrder: exercise.displayOrder
                )
            )
            print("  ✅ Created exercise: \(exercise.name)")
            
            // Add sets
            if let sets = exercise.sets, !sets.isEmpty {
                for set in sets {
                    try await apiService.addStrengthSet(
                        exerciseId: createdExercise.id,
                        set: set.toRequest()
                    )
                }
                print("    📝 Added \(sets.count) sets")
            }
        }
    }
    
    private func syncCardioWorkouts(_ workouts: [MappedCardioWorkout], date: Date) async throws {
        print("🏃 Syncing \(workouts.count) cardio workouts...")
        
        for (index, workout) in workouts.enumerated() {
            await updateStatus(.syncingCardio(index + 1, workouts.count))
            
            // Create the workout
            let createdWorkout = try await apiService.addCardioWorkout(
                date: date,
                workout: CardioWorkoutRequest(
                    name: workout.name,
                    modality: workout.modality,
                    notes: workout.notes,
                    coachNotes: workout.coachNotes,
                    displayOrder: workout.displayOrder
                )
            )
            print("  ✅ Created workout: \(workout.name) (\(workout.modality))")
            
            // Add intervals
            if let intervals = workout.intervals, !intervals.isEmpty {
                for interval in intervals {
                    try await apiService.addCardioInterval(
                        workoutId: createdWorkout.id,
                        interval: interval.toRequest()
                    )
                }
                print("    📝 Added \(intervals.count) intervals")
            }
        }
    }
    
    private func syncYogaMobility(_ yoga: MappedYogaMobility, date: Date) async throws {
        print("🧘 Syncing yoga/mobility workout...")
        await updateStatus(.syncingYoga)
        
        // Create/update the yoga workout
        let createdYoga = try await apiService.setYogaMobility(
            date: date,
            workout: yoga.toRequest()
        )
        print("  ✅ Created yoga/mobility: \(yoga.title ?? "Untitled")")
        
        // Add movements
        if let movements = yoga.movements, !movements.isEmpty {
            for movement in movements {
                try await apiService.addYogaMovement(
                    workoutId: createdYoga.id,
                    movement: movement.toRequest()
                )
            }
            print("    📝 Added \(movements.count) movements")
        }
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func updateStatus(_ newStatus: SyncStatus) {
        status = newStatus
    }
    
    private func formatDateForLog(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
