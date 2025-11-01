import SwiftUI

// MARK: - Settings View

/// Application settings interface for API configuration, developer options, and data management.
/// Handles API key management, feature toggles, and data clearing operations.
struct SettingsView: View {
    var onClearChat: () -> Void
    
    private let config = AppConfiguration.shared
    @State private var apiKey: String = AppConfiguration.shared.apiKey
    @State private var developerModeEnabled = UserDefaults.standard.bool(forKey: "DeveloperModeEnabled")
    @AppStorage("ShowAIReasoning") private var showAIReasoning = false
    @State private var showTimeControl = false

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
                
                Section("AI Features") {
                    Toggle("Show AI Reasoning", isOn: $showAIReasoning)
                    Text("Display the coach's internal reasoning process when planning workouts (requires GPT-5 or other reasoning models)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Developer Options") {
                    Group {
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
                        config.apiKey = apiKey
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