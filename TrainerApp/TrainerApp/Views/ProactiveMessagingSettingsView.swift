import SwiftUI

struct ProactiveMessagingSettingsView: View {
    @AppStorage("proactiveMessagingEnabled") private var enabled = true
    @AppStorage("proactiveCheckInterval") private var checkInterval = 30
    @AppStorage("proactiveMaxMessagesPerDay") private var maxMessagesPerDay = 3
    @AppStorage("proactiveQuietHoursEnabled") private var quietHoursEnabled = true
    @AppStorage("proactiveQuietHoursStart") private var quietHoursStart = 22
    @AppStorage("proactiveQuietHoursEnd") private var quietHoursEnd = 6
    @AppStorage("proactiveSundayReviewEnabled") private var sundayReviewEnabled = true
    @AppStorage("proactiveSundayReviewHour") private var sundayReviewHour = 19
    
    @State private var showTestButton = false
    @Environment(\.dismiss) private var dismiss
    
    private let intervalOptions = [15, 30, 45, 60, 90, 120]
    private let maxMessageOptions = [1, 2, 3, 5, 10]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Smart Reminders", isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            if newValue {
                                Task {
                                    await ProactiveCoachManager.shared.initialize()
                                }
                            }
                        }
                    
                    if enabled {
                        Text("Your coach will check in based on your workout patterns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Proactive Coaching")
                }
                
                if enabled {
                    Section {
                        Picker("Check Frequency", selection: $checkInterval) {
                            ForEach(intervalOptions, id: \.self) { interval in
                                Text("\(interval) minutes").tag(interval)
                            }
                        }
                        
                        Picker("Max Messages Per Day", selection: $maxMessagesPerDay) {
                            ForEach(maxMessageOptions, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                    } header: {
                        Text("Frequency")
                    }
                    
                    Section {
                        Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                        
                        if quietHoursEnabled {
                            HStack {
                                Text("From")
                                Spacer()
                                Picker("Start", selection: $quietHoursStart) {
                                    ForEach(0..<24) { hour in
                                        Text(formatHour(hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            
                            HStack {
                                Text("To")
                                Spacer()
                                Picker("End", selection: $quietHoursEnd) {
                                    ForEach(0..<24) { hour in
                                        Text(formatHour(hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    } header: {
                        Text("Do Not Disturb")
                    } footer: {
                        if quietHoursEnabled {
                            Text("No messages between \(formatHour(quietHoursStart)) and \(formatHour(quietHoursEnd))")
                        }
                    }
                    
                    Section {
                        Toggle("Sunday Weekly Review", isOn: $sundayReviewEnabled)
                        
                        if sundayReviewEnabled {
                            HStack {
                                Text("Review Time")
                                Spacer()
                                Picker("Time", selection: $sundayReviewHour) {
                                    ForEach(6..<22) { hour in
                                        Text(formatHour(hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    } header: {
                        Text("Weekly Progress")
                    } footer: {
                        if sundayReviewEnabled {
                            Text("Get a weekly summary every Sunday at \(formatHour(sundayReviewHour))")
                        }
                    }
                    
                    Section {
                        Button {
                            Task {
                                await testProactiveMessage()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Test Proactive Message")
                            }
                        }
                        
                        if showTestButton {
                            Text("Check your notifications!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Testing")
                    } footer: {
                        Text("Trigger a test evaluation to see what your coach would say right now")
                    }
                }
            }
            .navigationTitle("Smart Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        updateSettings()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        
        var components = DateComponents()
        components.hour = hour
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }
    
    private func updateSettings() {
        // Update ProactiveCoachManager settings
        var settings = ProactiveMessagingSettings()
        settings.enabled = enabled
        settings.checkFrequency = TimeInterval(checkInterval * 60)
        settings.maxMessagesPerDay = maxMessagesPerDay
        
        if quietHoursEnabled {
            settings.quietHoursStart = quietHoursStart
            settings.quietHoursEnd = quietHoursEnd
        } else {
            settings.quietHoursStart = nil
            settings.quietHoursEnd = nil
        }
        
        settings.sundayReviewEnabled = sundayReviewEnabled
        settings.sundayReviewTime = DateComponents(hour: sundayReviewHour, minute: 0)
        
        // Note: In a real implementation, we'd update ProactiveCoachManager.shared.settings
        // For now, the settings are stored in UserDefaults via @AppStorage
    }
    
    private func testProactiveMessage() async {
        await ProactiveCoachManager.shared.triggerEvaluation()
        
        withAnimation {
            showTestButton = true
        }
        
        // Hide the message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showTestButton = false
            }
        }
    }
}

#Preview {
    ProactiveMessagingSettingsView()
}