# Proactive Messaging Troubleshooting Guide

## Prerequisites Checklist

### 1. ✅ iOS Notification Permissions
- **Settings > Trainer > Notifications** must be enabled
- Allow Notifications must be ON
- Alert, Sound, and Badge should be enabled

### 2. ✅ In-App Settings
- Open Trainer app
- Go to Settings → Configure Smart Reminders
- Ensure "Enable Smart Reminders" is ON
- Make sure you have an OpenAI API key configured in Settings

### 3. ✅ First-Time Setup
When you first enable Smart Reminders, the app should:
1. Request notification permissions
2. Show a system dialog asking to allow notifications
3. You must tap "Allow"

## Common Issues & Solutions

### Issue: No notifications appear
**Solution 1**: Check Console Output
- Open Xcode console while testing
- Look for these messages:
  ```
  ✅ ProactiveCoachManager: Initialized successfully
  🤖 ProactiveCoachManager Decision:
     Send: Yes/No
     Reasoning: [explanation]
  ```

**Solution 2**: Force Notification Permission Request
- Delete the app from simulator/device
- Reinstall and run again
- When prompted, allow notifications

### Issue: "Suppressing check due to rules"
This means one of these conditions is true:
- App was opened in last 15 minutes
- Already sent max messages today
- Currently in quiet hours
- Message sent too recently

**Fix**: Use the "Test Proactive Message" button which bypasses these rules

### Issue: LLM not responding
Check for:
- Valid OpenAI API key in Settings
- Internet connection
- Console errors about API calls

## Testing Steps

### Method 1: Test Button (Recommended)
1. Open app
2. Settings → Configure Smart Reminders  
3. Enable Smart Reminders
4. Tap "Test Proactive Message"
5. Wait 5-10 seconds
6. Check notification center

### Method 2: Simulate Background Check
1. Enable Smart Reminders
2. Close the app completely
3. Wait for background refresh (30 min)
4. Or trigger manually in Xcode: Debug → Simulate Background Fetch

### Method 3: Check Simulator Settings
1. In iOS Simulator: Settings → Notifications → Trainer
2. Ensure all permissions are enabled
3. Check Do Not Disturb is OFF

## Debug Output to Expect

**Successful notification:**
```
📬 ProactiveCoachManager: Sent message: [message content]
```

**Permission denied:**
```
❌ ProactiveCoachManager: Failed to request permissions
```

**LLM decided not to send:**
```
🤖 ProactiveCoachManager Decision:
   Send: No
   Reasoning: [why not]
```

## Quick Fix Checklist
- [ ] Delete and reinstall app
- [ ] Allow notifications when prompted
- [ ] Verify API key is set
- [ ] Use Test button first
- [ ] Check console for errors
- [ ] Ensure not in Do Not Disturb mode