import SwiftUI

struct SimpleDeveloperTimeControl: View {
    @StateObject private var dateProvider = DateProvider.shared
    @StateObject private var scheduleManager = TrainingScheduleManager.shared
    @State private var daysToAdvance = 1
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
    
    var body: some View {
        VStack {
            Form {
                // Time Control Section
                VStack(alignment: .leading) {
                    Text("⏰ Time Control")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    Toggle("Test Mode", isOn: $dateProvider.isTestMode)
                        .onChange(of: dateProvider.isTestMode) { newValue in
                            if !newValue {
                                dateProvider.resetToRealTime()
                            }
                        }
                    
                    if dateProvider.isTestMode {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Real Time", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(dateFormatter.string(from: Date()))
                                .font(.system(.body, design: .monospaced))
                            
                            Label("Simulated Time", systemImage: "clock.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(dateFormatter.string(from: dateProvider.currentDate))
                                .font(.system(.body, design: .monospaced))
                                .bold()
                            
                            if dateProvider.currentDate != Date() {
                                let days = Calendar.current.dateComponents([.day], from: Date(), to: dateProvider.currentDate).day ?? 0
                                Text("\(abs(days)) day\(abs(days) == 1 ? "" : "s") \(days >= 0 ? "ahead" : "behind")")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical)
                
                // Quick Controls Section
                if dateProvider.isTestMode {
                    VStack(alignment: .leading) {
                        Text("🚀 Quick Controls")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        HStack(spacing: 12) {
                            Button(action: { dateProvider.advanceTime(by: -1) }) {
                                Label("−1 Day", systemImage: "arrow.backward")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { dateProvider.advanceTime(by: 1) }) {
                                Label("+1 Day", systemImage: "arrow.forward")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: { dateProvider.advanceTime(by: 7) }) {
                                Label("+7 Days", systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        HStack {
                            Text("Jump ahead:")
                            Stepper("\(daysToAdvance) day\(daysToAdvance == 1 ? "" : "s")", 
                                   value: $daysToAdvance, in: 1...30)
                        }
                        
                        Button(action: { dateProvider.advanceTime(by: daysToAdvance) }) {
                            Label("Jump \(daysToAdvance) Day\(daysToAdvance == 1 ? "" : "s") Forward", 
                                  systemImage: "forward.fill")
                        }
                        
                        Button(action: {
                            selectedDate = dateProvider.simulatedDate
                            showingDatePicker = true
                        }) {
                            Label("Set Specific Date...", systemImage: "calendar")
                        }
                        
                        Button(action: { dateProvider.resetToRealTime() }) {
                            Label("Reset to Current Time", systemImage: "arrow.counterclockwise")
                        }
                        .foregroundColor(.orange)
                    }
                    .padding(.vertical)
                    
                    // Quick Jumps Section
                    VStack(alignment: .leading) {
                        Text("📅 Quick Jumps")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Button("Jump to Week 2") {
                            dateProvider.jumpToWeek(2)
                        }
                        
                        Button("Jump to Block Transition (Week 5)") {
                            dateProvider.jumpToWeek(5)
                        }
                        
                        Button("Jump to Deload (Week 8)") {
                            dateProvider.jumpToWeek(8)
                        }
                        
                        Button("Jump to New Block (Week 9)") {
                            dateProvider.jumpToWeek(9)
                        }
                        
                        Button("Jump to Final Week (Week 16)") {
                            dateProvider.jumpToWeek(16)
                        }
                    }
                    .padding(.vertical)
                    
                    // Program State Section
                    VStack(alignment: .leading) {
                        Text("📊 Current Program State")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        if scheduleManager.currentProgram != nil {
                            HStack {
                                Text("Current Week")
                                Spacer()
                                Text("Week \(scheduleManager.currentWeek)")
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                            
                            HStack {
                                Text("Current Block")
                                Spacer()
                                Text(scheduleManager.currentBlock?.type.rawValue.replacingOccurrences(of: "-", with: " ").capitalized ?? "None")
                                    .bold()
                                    .foregroundColor(.green)
                            }
                            
                            HStack {
                                Text("Week in Block")
                                Spacer()
                                Text("\(scheduleManager.currentWeekInBlock)")
                                    .bold()
                            }
                            
                            HStack {
                                Text("Current Day")
                                Spacer()
                                Text(scheduleManager.currentDay.name)
                                    .bold()
                            }
                            
                            if let workout = scheduleManager.getWorkoutDay(for: dateProvider.currentDate) {
                                VStack(alignment: .leading) {
                                    Text("Today's Workout")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let planned = workout.plannedWorkout {
                                        Text(planned)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .padding(.top, 2)
                                    } else {
                                        Text("Rest Day")
                                            .font(.caption)
                                            .italic()
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Text("No active training program")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("🕐 Time Control")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                VStack {
                    DatePicker("Select Date", 
                              selection: $selectedDate,
                              displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Text("Selected: \(dayFormatter.string(from: selectedDate))")
                        .font(.headline)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Set Simulated Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Set") {
                            dateProvider.setSimulatedDate(selectedDate)
                            showingDatePicker = false
                        }
                        .bold()
                    }
                }
            }
        }
    }
}

struct SimpleDeveloperTimeControl_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SimpleDeveloperTimeControl()
        }
    }
}