# Universal log_set_result Schema Design

## Design Philosophy

Create ONE universal schema that elegantly handles ALL training modalities:
- 🏋️ Strength training (sets, reps, load, RIR)
- 🚣 Rowing/Erg (intervals, pace, SPM, heart rate)
- 🏃 Running (intervals, pace, distance, heart rate)
- 🚴 Cycling (intervals, power, cadence, heart rate)
- 🧘 Yoga/Mobility (duration, holds)

## Canonical Schema

### Required for ALL
- `exercise` (string) - Exercise/movement name

### Optional - Universal
- `date` (string, default "today") - Target date
- `notes` (string) - Additional notes

### Optional - Strength Training
- `set` (string) - Set number (e.g., "1", "2", "3")
- `reps` (string) - Repetitions (e.g., "8", "10")
- `load_lb` (string) - Weight in pounds (e.g., "135", "225")
- `rir` (string) - Reps in Reserve, 0-10 (e.g., "2", "3")

### Optional - Cardio/Intervals
- `interval` (string) - Interval/round number (e.g., "1", "2")
- `time` (string) - Duration (e.g., "5:30", "300", "5:30.2")
- `distance` (string) - Distance (e.g., "500m", "5000m", "2mi")
- `pace` (string) - Pace (e.g., "1:45/500m", "7:30/mi")
- `spm` (string) - Strokes/Steps Per Minute (e.g., "28", "32")
- `hr` (string) - Heart rate (e.g., "145", "165")
- `power` (string) - Power output in watts (e.g., "250", "180")
- `cadence` (string) - Cycling cadence in RPM (e.g., "85", "90")

## Modality Coverage

### 🏋️ Strength Training Examples

**Barbell Bench Press:**
```
log_set_result(
  exercise: "Bench Press",
  set: "1",
  reps: "8",
  load_lb: "185",
  rir: "2"
)
```

**Bodyweight Pull-ups:**
```
log_set_result(
  exercise: "Pull-up",
  set: "3",
  reps: "12",
  rir: "1"
)
```

### 🚣 Rowing/Erg Examples

**RowErg Interval:**
```
log_set_result(
  exercise: "RowErg Z2",
  interval: "1",
  time: "10:00",
  distance: "2400m",
  pace: "2:05/500m",
  spm: "20",
  hr: "145"
)
```

**RowErg Steady State:**
```
log_set_result(
  exercise: "RowErg Steady State",
  time: "30:00",
  distance: "7500m",
  pace: "2:00/500m",
  spm: "22",
  hr: "152"
)
```

### 🏃 Running Examples

**Interval Run:**
```
log_set_result(
  exercise: "Interval Run",
  interval: "3",
  time: "4:00",
  distance: "800m",
  pace: "5:00/mi",
  hr: "175"
)
```

**Easy Run:**
```
log_set_result(
  exercise: "Easy Run",
  time: "45:00",
  distance: "5mi",
  pace: "9:00/mi",
  hr: "135"
)
```

### 🚴 Cycling Examples

**BikeErg Interval:**
```
log_set_result(
  exercise: "BikeErg Sprint",
  interval: "2",
  time: "30",
  distance: "250m",
  power: "380",
  cadence: "110",
  hr: "182"
)
```

**Z2 Bike:**
```
log_set_result(
  exercise: "Z2 Bike",
  time: "60:00",
  distance: "20mi",
  power: "180",
  cadence: "85",
  hr: "145"
)
```

### 🧘 Yoga/Mobility Examples

**Yoga Hold:**
```
log_set_result(
  exercise: "Pigeon Pose",
  time: "2:00",
  notes: "Left side, deep stretch"
)
```

**Mobility Work:**
```
log_set_result(
  exercise: "Hip Flexor Stretch",
  time: "90",
  notes: "Right side, felt tight"
)
```

### 🏊 Swimming Example (Future)

**Swim Interval:**
```
log_set_result(
  exercise: "Freestyle",
  interval: "4",
  time: "1:30",
  distance: "100m",
  pace: "1:30/100m",
  spm: "18"
)
```

## Parameter Flexibility Rules

1. **No required combinations** - Coach can log whatever metrics are available
2. **Strength OR Cardio** - Don't mix `set/reps/load_lb` with `interval/time/distance`
3. **Backwards compatible** - Old data with `load_kg`, `rpe` still readable
4. **Forward compatible** - Easy to add new parameters (e.g., `elevation`, `temperature`)

## Data Model Updates Required

### WorkoutSetResult Model

**Current fields (keep):**
- `exerciseName`, `timestamp`, `notes`
- `setNumber`, `reps`, `loadLb`, `rir`

**Deprecate (backward compatible read only):**
- `loadKg` - Can still decode from old data
- `rpe` - Can still decode from old data

**Add new fields:**
```swift
// Cardio/Interval fields
let interval: Int?          // Interval/round number
let time: String?           // Duration (flexible format)
let distance: String?       // Distance with unit
let pace: String?           // Pace with unit
let spm: Int?               // Strokes/Steps Per Minute
let hr: Int?                // Heart rate BPM
let power: Int?             // Power in watts (cycling)
let cadence: Int?           // Cadence in RPM (cycling)
```

### Validation Rules

**Strength-specific validation:**
- If `set` OR `reps` OR `load_lb` OR `rir` present → Strength modality
- `rir` must be 0-10
- `reps` must be positive

**Cardio-specific validation:**
- If `interval` OR `time` OR `distance` OR `pace` present → Cardio modality
- `hr` must be 40-220 BPM (human range)
- `spm` must be positive
- `power` must be positive
- `cadence` must be positive

**Cross-validation:**
- WARN (not error) if mixing strength + cardio fields in same log
- Allow flexibility for hybrid movements (e.g., weighted row)

### Example Validation

```swift
private func validate() throws {
    // Exercise name
    let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let invalidNames = ["unknown", "exercise", "workout", "movement"]
    guard !trimmed.isEmpty && !invalidNames.contains(trimmed.lowercased()) && trimmed.count >= 2 else {
        throw WorkoutSetResultError.invalidExerciseName
    }
    
    // Strength validations
    if let rir = rir, rir < 0 || rir > 10 {
        throw WorkoutSetResultError.invalidRIR
    }
    if let reps = reps, reps <= 0 {
        throw WorkoutSetResultError.invalidReps
    }
    if let setNumber = setNumber, setNumber <= 0 {
        throw WorkoutSetResultError.invalidSetNumber
    }
    
    // Cardio validations
    if let hr = hr, hr < 40 || hr > 220 {
        throw WorkoutSetResultError.invalidHeartRate
    }
    if let spm = spm, spm <= 0 {
        throw WorkoutSetResultError.invalidSPM
    }
    if let power = power, power <= 0 {
        throw WorkoutSetResultError.invalidPower
    }
    if let cadence = cadence, cadence <= 0 {
        throw WorkoutSetResultError.invalidCadence
    }
}
```

## Migration Impact

### Backward Compatibility
✅ Old data with `loadKg`, `rpe` still decodes  
✅ New logs only write canonical schema  
✅ No data migration needed  

### Forward Compatibility
✅ Easy to add new fields (e.g., `elevation`, `temperature`, `felt_effort`)  
✅ Schema naturally extends to new modalities  
✅ Validation can be enhanced without breaking changes  

## SystemPrompt Updates

### Tool Documentation Structure

```markdown
### 7.5 `log_set_result`

**Purpose:** Log workout data for ANY training modality (strength, cardio, mobility)

**Required:**
* `exercise` (string) - Specific exercise/movement name

**Optional - Universal:**
* `date` (string) - Target date (default: "today")
* `notes` (string) - Additional notes

**Optional - Strength Training:**
* `set` (string) - Set number
* `reps` (string) - Repetitions
* `load_lb` (string) - Weight in pounds
* `rir` (string) - Reps in Reserve (0-10)

**Optional - Cardio/Intervals:**
* `interval` (string) - Interval/round number
* `time` (string) - Duration (formats: "5:30", "300", "5:30.2")
* `distance` (string) - Distance (e.g., "500m", "2mi", "5k")
* `pace` (string) - Pace (e.g., "1:45/500m", "7:30/mi")
* `spm` (string) - Strokes/Steps Per Minute
* `hr` (string) - Heart rate (BPM)
* `power` (string) - Power output (watts, cycling)
* `cadence` (string) - Cadence (RPM, cycling)

**Usage - Strength:**
```
log_set_result(exercise: "Bench Press", set: "1", reps: "8", load_lb: "185", rir: "2")
```

**Usage - Rowing:**
```
log_set_result(exercise: "RowErg Z2", interval: "1", time: "10:00", distance: "2400m", pace: "2:05/500m", spm: "20", hr: "145")
```

**Usage - Running:**
```
log_set_result(exercise: "Interval Run", interval: "3", time: "4:00", distance: "800m", pace: "5:00/mi", hr: "175")
```

**Schema Rules:**
1. Parameter names are case-sensitive and must match exactly
2. Use `exercise` (NOT `exerciseName`, `movement`, or `name`)
3. Use `load_lb` (NOT `load_kg` or `weight_lb`)
4. Use `rir` (NOT `rpe`)
5. Use `spm` for rowing stroke rate OR running cadence
6. Don't mix strength + cardio fields in same log (e.g., don't use `set` AND `interval`)
```

## Implementation Checklist

### Phase 1: Data Model
- [ ] Add new fields to `WorkoutSetResult.swift`: `interval`, `time`, `distance`, `pace`, `spm`, `hr`, `power`, `cadence`
- [ ] Add validation for new fields
- [ ] Add error types: `invalidHeartRate`, `invalidSPM`, `invalidPower`, `invalidCadence`
- [ ] Mark `loadKg`, `rpe` as deprecated (keep for backward compat)
- [ ] Update CodingKeys to support new fields

### Phase 2: Tool Executor
- [ ] Update `WorkoutToolExecutor.swift` to extract new cardio parameters
- [ ] Remove aliases for all parameters (strict schema)
- [ ] Add guard for required `exercise` parameter
- [ ] Add helpful error detection for common mistakes
- [ ] Update success message format to show relevant fields

### Phase 3: System Prompt
- [ ] Rewrite tool documentation with universal schema
- [ ] Add examples for each modality (strength, rowing, running, cycling)
- [ ] Emphasize strict parameter naming
- [ ] Add troubleshooting tips

### Phase 4: View Layer
- [ ] Update `ResultsSection` in `WeeklyCalendarView.swift` to display cardio fields
- [ ] Add icons/formatting for different modalities
- [ ] Format time/pace appropriately

### Phase 5: Testing
- [ ] Unit tests for strength logging
- [ ] Unit tests for cardio logging (rowing, running, cycling)
- [ ] Unit tests for mobility logging
- [ ] Validation tests for new fields
- [ ] Integration tests with coach

## Success Metrics

- 🎯 Zero "Unknown" exercise entries
- 🎯 Support logging for strength, cardio, and mobility in same tool
- 🎯 Clear error messages for missing/invalid parameters
- 🎯 Backward compatible with existing data
- 🎯 LLM successfully logs all modality types within 1 week

## Open Questions

1. **Time format flexibility:** Should we parse multiple formats ("5:30", "330", "5:30.2") or enforce one?
   - **Recommendation:** Accept string, parse on display - flexible for coach

2. **Unit enforcement:** Should `distance` include unit ("500m") or separate field?
   - **Recommendation:** Include unit in string - simpler schema

3. **Pace format:** How to handle different pace formats (split time vs. MPH)?
   - **Recommendation:** String format, parse on display - most flexible

4. **Mixed modality:** What if workout combines strength + cardio (e.g., weighted row)?
   - **Recommendation:** Allow but warn - log twice if needed

5. **Swimming parameters:** Do we need `stroke_type` (freestyle, backstroke)?
   - **Recommendation:** Include in `exercise` name for now - e.g., "Freestyle Intervals"