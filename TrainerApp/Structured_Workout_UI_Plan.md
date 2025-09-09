# Structured Workout UI — Concise Implementation Plan

Objective
- Replace the unstructured workout text with a clear, per‑exercise UI driven by structured JSON.
- Use existing tools (no new tools) by extending parameters.
- Stop persisting and rendering plain text workouts; all new workouts must be structured.

Scope
- Data model: add/persist StructuredWorkout on the day; retain legacy fields only for backward read.
- Tools: extend existing plan_workout and update_workout to accept structured JSON.
- Manager: save/update structured workout and metadata; persist with Codable.
- UI: render per‑exercise cards only; remove text fallback.
- Prompt: update to always use structured JSON via existing tools.
- Logging, validation, and tests included.

Files to change
- [TrainerApp/TrainerApp/Models/TrainingCalendar.swift](TrainerApp/TrainerApp/Models/TrainingCalendar.swift)
- [TrainerApp/TrainerApp/Services/ToolProcessor.swift](TrainerApp/TrainerApp/Services/ToolProcessor.swift)
- [TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift](TrainerApp/TrainerApp/Managers/TrainingScheduleManager.swift)
- [TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift](TrainerApp/TrainerApp/Views/WeeklyCalendarView.swift)
- [TrainerApp/TrainerApp/Views/CalendarView.swift](TrainerApp/TrainerApp/Views/CalendarView.swift)
- [TrainerApp/TrainerApp/SystemPrompt.md](TrainerApp/TrainerApp/SystemPrompt.md)

Data model
- StructuredWorkout (Codable, evolvable) with top‑level fields like title, summary, durationMinutes, notes, and exercises.
- Exercise supports multiple kinds (cardio, strength, mobility, yoga, generic) with detail payloads.
- Unknown keys tolerated to allow schema evolution.
- Extend WorkoutDay with structuredWorkout: StructuredWorkout?
- Do not write plannedWorkout anymore; keep it only for legacy loads (no UI usage).
- Continue to store workoutIcon; derive icon from structuredWorkout when none is provided.

Tools (extend existing, no new tools)
- plan_workout: add required parameter workout_json (string). Optional notes and icon remain supported.
- update_workout: add required parameter workout_json (string). Optional notes and icon remain supported.
- Behavior:
  - Parse date inputs (“today”, “YYYY-MM-DD”) using existing utilities.
  - Decode workout_json into StructuredWorkout; if decoding fails, return a concise error with hint (no crash).
  - Persist via manager:
    - Set structuredWorkout, coachNotes (if provided), workoutIcon (if provided), lastModified (use DateProvider.current).
    - Do not modify plannedWorkout.
  - Return deep link trainer://calendar/YYYY-MM-DD plus a compact summary derived from the structured workout.
- Logging:
  - Success: “Saved structured workout with N exercises; distribution: cardio X, strength Y, mobility Z, yoga W.”
  - Failure: “Decoding structured workout JSON failed: [reason] at [path].”

Manager updates
- Add APIs to save/update structured workouts, e.g. planStructuredWorkout and updateStructuredWorkout (names descriptive; exact signatures implemented in code mode).
- Find or create the day; set structuredWorkout, coachNotes, workoutIcon, lastModified (DateProvider.current).
- Ensure Codable persistence includes structuredWorkout for all save/load paths, including iCloud/UserDefaults.
- Do not write plannedWorkout anywhere in these paths.

UI
- Day detail: show a new StructuredWorkoutView when structuredWorkout exists; remove the text block entirely.
  - Header: title/summary, total duration, day icon.
  - Exercises list:
    - Cardio card: modality, total duration/distance, interval table (repeat × work/rest × targets).
    - Strength card: sets table (Set, Reps, Weight, Tempo, RIR, Rest); superset grouping labels as needed.
    - Mobility card: movement list with holds/durations and sides.
    - Yoga card: block/sequence list with durations.
    - Generic card: bullet items.
  - Coach notes (optional) rendered after the list.
- Weekly/Monthly tiles: prefer coach-selected icon; otherwise derive from the first exercise kind; otherwise “no workout”.
- Accessibility: add VoiceOver descriptions for intervals/targets; support Dynamic Type; avoid dense layouts on compact width.

System prompt
- Update instructions to always use existing tools with workout_json for any workout planning or updating.
- Provide concise examples across cardio intervals, strength, mobility, and yoga that fit the schema.
- Keep chat messages short, referencing the returned deep link; no long workout text in chat.

Validation and error handling
- Reject missing or invalid workout_json with a clear, single‑line error.
- Tolerate unknown keys; ignore non‑critical fields gracefully.
- Cap maximum exercises displayed (e.g., 30) with a “show more” control to prevent oversized payload UI issues.

Testing
- Unit tests:
  - JSON decoding for each exercise kind and unknown‑key tolerance.
  - Tool success and error paths (decoding error surfaces cleanly).
  - Manager round‑trip persistence of structuredWorkout.
- UI previews:
  - One preview per card type plus a composite mixed‑modality preview.
- Manual verification:
  - Chat → plan_workout with workout_json → deep link → per‑exercise UI renders.
  - Chat → update_workout with modified workout_json → UI updates accordingly.
  - Weekly/Monthly tiles show correct icons/derivation.

Non‑goals and migration
- Do not render or write plannedWorkout text anywhere going forward.
- Keep plannedWorkout property only for legacy decoding; no migration within this PR.
- Detailed instructions feature remains separate and optional, not required for the per‑exercise UI.

Acceptance criteria
- New and updated workouts must be created through plan_workout/update_workout with workout_json.
- StructuredWorkout is persisted and rendered as per‑exercise cards; no text fallback remains.
- Tiles show coach-selected icon or a derived icon from structured content.
- All date/time operations use DateProvider.current (never Date()) in managers/views.
- Prompt changes cause the coach to regularly provide workout_json, and tool logs confirm structured saves.

Execution notes
- Follow repository rules (.roorules) for build commands and relative paths.
- Keep file references relative to the workspace root.
- Ensure the manager and ToolProcessor changes are coordinated so that decoding and persistence succeed atomically.