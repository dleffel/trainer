import Foundation

// MARK: - Date Provider for Testing
class DateProvider: ObservableObject {
    static let shared = DateProvider()
    
    @Published var isTestMode: Bool = false
    @Published var simulatedDate: Date = Date()
    private var timeOffset: TimeInterval = 0
    
    private init() {
        loadTestState()
    }
    
    var currentDate: Date {
        if isTestMode {
            return simulatedDate
        }
        return Date()
    }
    
    func advanceTime(by days: Int) {
        guard isTestMode else { return }
        simulatedDate = Calendar.current.date(byAdding: .day, value: days, to: simulatedDate) ?? simulatedDate
        timeOffset = simulatedDate.timeIntervalSince(Date())
        saveTestState()
    }
    
    func setSimulatedDate(_ date: Date) {
        simulatedDate = date
        timeOffset = date.timeIntervalSince(Date())
        saveTestState()
    }
    
    func resetToRealTime() {
        isTestMode = false
        simulatedDate = Date()
        timeOffset = 0
        clearTestState()
    }
    
    // Jump to specific week in program
    func jumpToWeek(_ week: Int) {
        guard let programStart = UserDefaults.standard.object(forKey: "TrainingProgram") as? Data,
              let program = try? JSONDecoder().decode(TrainingProgram.self, from: programStart),
              let startDate = program.startDate as Date? else { return }
        
        let daysToAdd = (week - 1) * 7
        if let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: startDate) {
            setSimulatedDate(targetDate)
        }
    }
    
    // Persistence
    private func saveTestState() {
        UserDefaults.standard.set(isTestMode, forKey: "DateProvider_TestMode")
        UserDefaults.standard.set(simulatedDate, forKey: "DateProvider_SimulatedDate")
        UserDefaults.standard.set(timeOffset, forKey: "DateProvider_TimeOffset")
    }
    
    private func loadTestState() {
        if UserDefaults.standard.bool(forKey: "DateProvider_TestMode") {
            isTestMode = true
            simulatedDate = UserDefaults.standard.object(forKey: "DateProvider_SimulatedDate") as? Date ?? Date()
            timeOffset = UserDefaults.standard.double(forKey: "DateProvider_TimeOffset")
        }
    }
    
    private func clearTestState() {
        UserDefaults.standard.removeObject(forKey: "DateProvider_TestMode")
        UserDefaults.standard.removeObject(forKey: "DateProvider_SimulatedDate")
        UserDefaults.standard.removeObject(forKey: "DateProvider_TimeOffset")
    }
}

// MARK: - Date Extension for Easy Replacement
extension Date {
    /// Use Date.current instead of Date() for testable code
    /// This will return the simulated date when in test mode
    static var current: Date {
        return DateProvider.shared.currentDate
    }
    
    /// Alternative name for clarity
    static var now: Date {
        return DateProvider.shared.currentDate
    }
    
    /// For real timestamps (logging, API calls, etc)
    /// Always returns the actual current date/time
    static var realTime: Date {
        return Date()
    }
}

// MARK: - Helper for decoding TrainingProgram
// We use the existing TrainingProgram struct from TrainingBlock.swift