# iCloud Sync Troubleshooting Guide

## Issue: "iCloud is available" but no "Saved to iCloud" message

### What You Should See After Sending a Message:

1. `💾 Persist called with X messages`
2. `☁️ Saved to iCloud (X bytes) - Sync started: true`
3. `✅ Verified: Data exists in iCloud store (X bytes)`

### If You're Not Seeing These:

## 1. Check iCloud Settings on Device

**On iOS Simulator/Device:**
- Settings → [Your Name] → iCloud
- Ensure **iCloud Drive** is ON (not just CloudKit)
- Scroll down to "Apps Using iCloud Drive"
- Your app should appear here

**Important:** NSUbiquitousKeyValueStore requires iCloud Drive, not just CloudKit!

## 2. Add iCloud Documents Capability

The current entitlements only have CloudKit. You need to add iCloud Documents:

In `TrainerApp.entitlements` and `TrainerAppDebug.entitlements`, update:

```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
    <string>CloudDocuments</string>
</array>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

## 3. Test with a Debug Button

Add this temporary debug button to ContentView to test iCloud directly:

```swift
Button("Test iCloud Save") {
    let testData = ["test": "Hello iCloud at \(Date())"]
    if let data = try? JSONEncoder().encode(testData) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: "test_key")
        let synced = store.synchronize()
        print("🧪 Test save - Sync started: \(synced)")
        
        if let saved = store.data(forKey: "test_key") {
            print("✅ Test data verified in store")
        } else {
            print("❌ Test data NOT in store")
        }
    }
}
```

## 4. Check Console for Errors

Filter Xcode console by "iCloud" or "NSUbiquitous" to see system messages.

## 5. Common Issues & Solutions

### Issue: persist() not being called
- Check console for `💾 Persist called` message
- If missing, the save isn't happening at all

### Issue: Data too large
- Check for `⚠️ Data too large` message
- Key-value store has 1MB limit

### Issue: iCloud Drive not enabled
- Most common issue!
- Must enable iCloud Drive, not just sign into iCloud

### Issue: Wrong container
- Verify bundle ID matches: `com.dannyleffel.organizer.TrainerApp`
- Check container in CloudKit dashboard

## 6. Force iCloud Sync

Add this to manually trigger sync:

```swift
.onAppear {
    // Force immediate sync
    NSUbiquitousKeyValueStore.default.synchronize()
}
```

## 7. Reset and Test

1. Delete app from all devices
2. Sign out/in to iCloud
3. Reinstall app
4. Send test message
5. Check console output

## Quick Fix Attempt

Try adding this to the beginning of `save()` function:

```swift
func save(_ messages: [ChatMessage]) throws {
    // Force sync at start
    keyValueStore.synchronize()
    
    // ... rest of save code
}
```

## If Still Not Working

1. Share the full console output when sending a message
2. Confirm iCloud Drive is enabled (not just iCloud)
3. Try the test button to isolate the issue
4. Check if the app appears in Settings → iCloud → Manage Storage

The most common issue is iCloud Drive not being enabled!