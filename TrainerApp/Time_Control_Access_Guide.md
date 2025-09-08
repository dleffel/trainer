# How to Access Time Control Feature

## Quick Steps

1. **Open TrainerApp**
2. **Tap Settings** (gear icon in top toolbar)
3. **Scroll to "Developer Options" section**
4. **Enable "Developer Mode" toggle** ← This is the key step!
5. **New options appear including "Time Control"**
6. **Tap "Time Control" button** (clock icon)

## Visual Flow

```
Settings
  └── Developer Options
      ├── Developer Mode [Toggle this ON first]
      └── (Once enabled, these appear:)
          ├── API Logging [Toggle]
          ├── View API Logs [Button]
          └── Time Control [Button] ← This opens time simulation!
```

## Troubleshooting

### Don't see Developer Options?
- Make sure you're in the Settings view (gear icon)
- Scroll down past the API Configuration section

### Don't see Time Control button?
- **Developer Mode must be enabled first**
- Once you toggle Developer Mode ON, Time Control appears below

### Time Control not working?
- Ensure the app was rebuilt with the latest changes
- Check that DateProvider.swift and SimpleDeveloperTimeControl.swift are included in the project

## What You'll See

Once you tap Time Control, you'll get:
- Test Mode toggle (enable/disable time simulation)
- Current simulated date display
- Quick jump buttons (Week 1, 5, 9, 13)
- Time advancement controls (+1 hour, +1 day)

## Important Notes

- Developer Mode is persisted in UserDefaults
- Once enabled, it stays on between app launches
- Time Control changes affect all date-dependent features
- Disable Test Mode to return to real time