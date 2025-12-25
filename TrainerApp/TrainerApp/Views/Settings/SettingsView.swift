import SwiftUI

// MARK: - Settings View

/// Application settings interface for API configuration, developer options, and data management.
/// Handles API key management, feature toggles, and data clearing operations.
struct SettingsView: View {
    var onClearChat: () -> Void
    
    private let config = AppConfiguration.shared
    private let organizerCredentials = ExerciseAPICredentials.shared
    
    @State private var apiKey: String = AppConfiguration.shared.apiKey
    @State private var developerModeEnabled = UserDefaults.standard.bool(forKey: "DeveloperModeEnabled")
    @AppStorage("ShowAIReasoning") private var showAIReasoning = false
    @State private var showTimeControl = false
    
    // Organizer API credentials
    @State private var organizerEmail: String = ExerciseAPICredentials.shared.email
    @State private var organizerPassword: String = ExerciseAPICredentials.shared.password
    @State private var showPasswordFormatError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter") {
                    SecureField("API Key (sk-or-...)", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("Get your API key at [openrouter.ai](https://openrouter.ai)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Organizer API") {
                    TextField("Email", text: $organizerEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    
                    SecureField("App Password (xxxx-xxxx-xxxx-xxxx-xxxx-xxxx)", text: $organizerPassword)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    
                    Text("Generate an app password in Organizer → Settings → App Passwords. Used for syncing workout data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if organizerCredentials.hasCredentials {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Credentials configured")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Section("AI Features") {
                    Toggle("Show AI Reasoning", isOn: $showAIReasoning)
                    Text("Display the coach's internal reasoning process when planning workouts (requires GPT-5 or other reasoning models)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Developer Options") {
                    Toggle("Developer Mode", isOn: $developerModeEnabled)
                        .onChange(of: developerModeEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "DeveloperModeEnabled")
                        }
                    
                    if developerModeEnabled {
                        Button {
                            showTimeControl = true
                        } label: {
                            Label("Time Control", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        onClearChat()
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                    
                    Button(role: .destructive) {
                        clearWorkoutData()
                    } label: {
                        Label("Clear Workout Data", systemImage: "calendar.badge.minus")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                }
            }
        }
        .sheet(isPresented: $showTimeControl) {
            NavigationView {
                SimpleDeveloperTimeControl()
            }
            .presentationDetents([.large])
        }
        .alert("Invalid Password Format", isPresented: $showPasswordFormatError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The app password should be in the format: xxxx-xxxx-xxxx-xxxx-xxxx-xxxx (6 groups of 4 characters separated by dashes)")
        }
    }
    
    // MARK: - Save Settings
    
    private func saveSettings() {
        // Save OpenRouter API key
        config.apiKey = apiKey
        
        // Validate and save Organizer credentials
        let trimmedEmail = organizerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = organizerPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only validate password format if one is provided
        if !trimmedPassword.isEmpty && !organizerCredentials.validatePasswordFormat(trimmedPassword) {
            showPasswordFormatError = true
            return
        }
        
        organizerCredentials.email = trimmedEmail
        organizerCredentials.password = trimmedPassword
        
        print("✅ Settings saved - OpenRouter: \(apiKey.isEmpty ? "not set" : "configured"), Organizer: \(organizerCredentials.hasCredentials ? "configured" : "not set")")
    }
    
    // MARK: - Private Helpers
    
    private func clearWorkoutData() {
        // Clear workout data without starting a new program
        let manager = TrainingScheduleManager.shared
        manager.currentProgram = nil
        manager.currentBlock = nil
        manager.workoutDays = []
        
        // Clear all workout data using TrainingScheduleManager's proper clear method
        TrainingScheduleManager.shared.restartProgram()
        
        // Also clear any remaining workout keys using brute force approach
        let userDefaults = UserDefaults.standard
        let iCloudStore = NSUbiquitousKeyValueStore.default
        
        // Clear all keys starting with "workout_" from UserDefaults
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("workout_") {
                userDefaults.removeObject(forKey: key)
                print("🧹 Cleared UserDefaults key: \(key)")
            }
        }
        
        // For iCloud, we'll rely on TrainingScheduleManager's clear method
        // since NSUbiquitousKeyValueStore doesn't provide a way to list all keys
        iCloudStore.synchronize()
        
        print("✅ All workout data cleared using comprehensive approach")
    }
}