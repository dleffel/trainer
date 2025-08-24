import Foundation
import HealthKit

/// Manager class for handling HealthKit data operations
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    /// Health data model containing all requested metrics
    struct HealthData {
        var weight: Double? // in pounds
        var timeAsleepHours: Double?
        var bodyFatPercentage: Double?
        var leanBodyMass: Double? // in pounds
        var height: Double? // in feet and inches (e.g., 6.17 for 6'2")
        var lastUpdated: Date
        
        /// Convert to dictionary for easy JSON serialization
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = ["lastUpdated": lastUpdated.ISO8601Format()]
            
            if let weight = weight {
                dict["weight"] = weight
            }
            if let timeAsleepHours = timeAsleepHours {
                dict["timeAsleepHours"] = timeAsleepHours
            }
            if let bodyFatPercentage = bodyFatPercentage {
                dict["bodyFatPercentage"] = bodyFatPercentage
            }
            if let leanBodyMass = leanBodyMass {
                dict["leanBodyMass"] = leanBodyMass
            }
            if let height = height {
                dict["height"] = height
            }
            
            return dict
        }
    }
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Request authorization to read health data
    func requestAuthorization() async throws -> Bool {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }
        
        // Define the types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .height)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Data Fetching
    
    /// Fetch all health data
    func fetchHealthData() async throws -> HealthData {
        var healthData = HealthData(lastUpdated: Date())
        
        // Fetch each metric concurrently
        async let weight = fetchLatestWeight()
        async let bodyFat = fetchLatestBodyFatPercentage()
        async let leanMass = fetchLatestLeanBodyMass()
        async let height = fetchLatestHeight()
        async let sleep = fetchSleepHours(for: Date())
        
        // Await all results
        healthData.weight = try? await weight
        healthData.bodyFatPercentage = try? await bodyFat
        healthData.leanBodyMass = try? await leanMass
        healthData.height = try? await height
        healthData.timeAsleepHours = try? await sleep
        
        return healthData
    }
    
    // MARK: - Individual Metric Fetchers
    
    private func fetchLatestWeight() async throws -> Double {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let sample = try await fetchMostRecentSample(for: weightType)
        let weightInKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        return weightInKg * 2.20462 // Convert kg to pounds
    }
    
    private func fetchLatestBodyFatPercentage() async throws -> Double {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let sample = try await fetchMostRecentSample(for: bodyFatType)
        return sample.quantity.doubleValue(for: .percent()) * 100 // Convert to percentage
    }
    
    private func fetchLatestLeanBodyMass() async throws -> Double {
        guard let leanMassType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let sample = try await fetchMostRecentSample(for: leanMassType)
        let massInKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        return massInKg * 2.20462 // Convert kg to pounds
    }
    
    private func fetchLatestHeight() async throws -> Double {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        let sample = try await fetchMostRecentSample(for: heightType)
        let heightInMeters = sample.quantity.doubleValue(for: .meter())
        let heightInInches = heightInMeters * 39.3701
        let feet = Int(heightInInches / 12)
        let inches = heightInInches.truncatingRemainder(dividingBy: 12)
        return Double(feet) + (inches / 100) // Return as 6.02 for 6'2"
    }
    
    private func fetchSleepHours(for date: Date) async throws -> Double {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.dataTypeNotAvailable
        }
        
        // Get sleep data for the last 24 hours
        let endDate = date
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                
                // Calculate total sleep time (excluding "in bed" time)
                let asleepSamples = samples.filter { sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    return value == .asleepREM || value == .asleepDeep || value == .asleepCore || value == .asleep
                }
                
                let totalSeconds = asleepSamples.reduce(0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                
                let hours = totalSeconds / 3600
                continuation.resume(returning: hours)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchMostRecentSample(for type: HKQuantityType) async throws -> HKQuantitySample {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(throwing: HealthKitError.noData)
                    return
                }
                
                continuation.resume(returning: sample)
            }
            
            healthStore.execute(query)
        }
    }
}

// MARK: - Error Types

enum HealthKitError: LocalizedError {
    case notAvailable
    case dataTypeNotAvailable
    case noData
    case authorizationFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .dataTypeNotAvailable:
            return "The requested data type is not available"
        case .noData:
            return "No data found for the requested type"
        case .authorizationFailed:
            return "HealthKit authorization failed"
        }
    }
}