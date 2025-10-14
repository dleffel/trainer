import Foundation

/// Manages training program lifecycle and state
/// Extracted from TrainingScheduleManager for better separation of concerns
class TrainingProgramManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var currentProgram: TrainingProgram?
    
    // MARK: - Dependencies
    
    private let programStore: HybridCloudStore<TrainingProgram>
    private let workoutStore: HybridCloudStore<WorkoutDay>
    private let resultsManager: WorkoutResultsManager
    
    // Callback for when program changes (so manager can update blocks)
    var onProgramChanged: (() -> Void)?
    
    // MARK: - Initialization
    
    init(programStore: HybridCloudStore<TrainingProgram>,
         workoutStore: HybridCloudStore<WorkoutDay>,
         resultsManager: WorkoutResultsManager = .shared) {
        self.programStore = programStore
        self.workoutStore = workoutStore
        self.resultsManager = resultsManager
        
        // Setup cloud change handler
        programStore.onCloudChange = { [weak self] in
            self?.loadProgram()
        }
        
        loadProgram()
    }
    
    // MARK: - Program Lifecycle
    
    /// Start a new training program
    func startProgram(startDate: Date = Date.current) {
        let program = TrainingProgram(startDate: startDate, currentMacroCycle: 1)
        self.currentProgram = program
        saveProgram()
        onProgramChanged?()
    }
    
    /// Load existing program from storage
    func loadProgram() {
        if let program = programStore.load(forKey: PersistenceKey.Training.program) {
            self.currentProgram = program
            onProgramChanged?()
        }
    }
    
    /// Save program to storage
    func saveProgram() {
        guard let program = currentProgram else { return }
        
        do {
            try programStore.save(program, forKey: PersistenceKey.Training.program)
        } catch {
            print("❌ Failed to save program: \(error)")
        }
    }
    
    /// Restart training program with comprehensive data clearing
    func restartProgram(startDate: Date = Date.current) {
        // Clear old program data
        currentProgram = nil
        
        // Clear program using persistence layer
        do {
            try programStore.delete(forKey: PersistenceKey.Training.program)
        } catch {
            print("⚠️ Failed to clear program: \(error)")
        }
        
        // Clear workout days using clearRange
        let calendar = Calendar.current
        let startClearDate = calendar.date(byAdding: .year, value: -1, to: Date.current)!
        let endClearDate = calendar.date(byAdding: .year, value: 1, to: Date.current)!
        
        do {
            try workoutStore.clearRange(from: startClearDate, to: endClearDate)
        } catch {
            print("⚠️ Failed to clear workout days: \(error)")
        }
        
        // Clear results using WorkoutResultsManager
        resultsManager.clearResults(from: startClearDate, to: endClearDate)
        
        // Start fresh program
        startProgram(startDate: startDate)
    }
    
    // MARK: - Accessors
    
    /// Get the program start date
    var programStartDate: Date? {
        return currentProgram?.startDate
    }
}