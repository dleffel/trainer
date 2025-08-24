# Apple Health Age Integration Plan

## Overview
This plan outlines how to add age retrieval functionality from Apple HealthKit to the TrainerApp.

## Technical Details

### 1. HealthKit Age/Date of Birth Access
- Apple Health stores date of birth as a `HKCharacteristicType`
- Use `HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)`
- This is different from quantity types (weight, height) and category types (sleep)
- Characteristic types are user profile data that doesn't change frequently

### 2. Implementation Steps

#### Step 1: Update Authorization Request
Add date of birth to the types we request authorization for:
```swift
let characteristicTypes: Set<HKObjectType> = [
    HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
]
```

#### Step 2: Add Age to HealthData Struct
```swift
struct HealthData {
    var weight: Double? // in pounds
    var timeAsleepHours: Double?
    var bodyFatPercentage: Double?
    var leanBodyMass: Double? // in pounds
    var height: Double? // in feet and inches
    var age: Int? // in years
    var dateOfBirth: Date?
    var lastUpdated: Date
}
```

#### Step 3: Create Age Fetching Method
```swift
private func fetchDateOfBirth() async throws -> (date: Date, age: Int) {
    guard let dateOfBirthType = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) else {
        throw HealthKitError.dataTypeNotAvailable
    }
    
    // Check authorization status
    let status = healthStore.authorizationStatus(for: dateOfBirthType)
    guard status == .sharingAuthorized else {
        throw HealthKitError.authorizationFailed
    }
    
    // Fetch date of birth
    guard let dateOfBirth = try? healthStore.dateOfBirthComponents().date else {
        throw HealthKitError.noData
    }
    
    // Calculate age
    let calendar = Calendar.current
    let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
    guard let age = ageComponents.year else {
        throw HealthKitError.noData
    }
    
    return (dateOfBirth, age)
}
```

#### Step 4: Update fetchHealthData Method
Add age fetching to the concurrent operations:
```swift
async let ageData = fetchDateOfBirth()
// ...
let ageInfo = try? await ageData
healthData.age = ageInfo?.age
healthData.dateOfBirth = ageInfo?.date
```

#### Step 5: Update toDictionary Method
Include age in the dictionary output:
```swift
if let age = age {
    dict["age"] = age
}
if let dateOfBirth = dateOfBirth {
    dict["dateOfBirth"] = dateOfBirth.ISO8601Format()
}
```

### 3. Privacy Considerations
- Date of birth is sensitive personal information
- Requires explicit user permission in Info.plist
- Add to Info.plist: `NSHealthShareUsageDescription` should mention age/date of birth access
- Users can deny access to date of birth while allowing other health data

### 4. Error Handling
- Handle case where user hasn't entered their date of birth in Health app
- Handle authorization denial specifically for date of birth
- Provide graceful fallback when age is unavailable

### 5. Alternative Approaches
If direct date of birth access is denied or unavailable:
1. Allow manual age input in the app
2. Use age ranges instead of exact age
3. Calculate approximate age from other health metrics (less accurate)

## Benefits
- Accurate age calculation based on authoritative source
- Automatic age updates (no need for user to update manually)
- Integration with existing health data flow
- Can be used for age-adjusted fitness recommendations

## Testing Checklist
- [ ] Test with user who has date of birth in Health app
- [ ] Test with user who doesn't have date of birth set
- [ ] Test authorization denial scenario
- [ ] Test age calculation accuracy
- [ ] Verify privacy compliance