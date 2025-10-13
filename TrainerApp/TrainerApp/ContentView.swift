import SwiftUI
import Foundation
import UniformTypeIdentifiers
import HealthKit
import CloudKit
import PhotosUI

// MARK: - Main App View with Tab Navigation

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var showSettings: Bool = false
    @State private var errorMessage: String?
    @State private var iCloudAvailable = false
    @State private var showMigrationAlert: Bool = false
    
    // Navigation state for deep linking and tab selection
    @EnvironmentObject var navigationState: NavigationState

    private let healthKitManager = HealthKitManager.shared
    private let config = AppConfiguration.shared

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            ChatView(
                conversationManager: conversationManager,
                showSettings: $showSettings,
                iCloudAvailable: iCloudAvailable
            )
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(0)
            
            CalendarTabView(showSettings: $showSettings)
                .tabItem {
                    Label("Log", systemImage: "calendar")
                }
                .tag(1)
        }
        .onAppear {
            setupOnAppear()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                onClearChat: {
                    Task {
                        await conversationManager.clearConversation()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .alert("API Key Migration Required", isPresented: $showMigrationAlert, actions: {
            Button("Open Settings") {
                showSettings = true
            }
            Button("Later", role: .cancel) { }
        }, message: {
            Text("OpenRouter API key required — update in Settings")
        })
    }
    
    // MARK: - Setup & Helpers
    
    private func setupOnAppear() {
        // Initialize conversation manager
        Task {
            await conversationManager.initialize()
        }
        
        // Check iCloud availability
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                iCloudAvailable = status == .available
                if !iCloudAvailable {
                    print("⚠️ iCloud not available")
                } else {
                    print("✅ iCloud is available")
                }
            }
        }
        
        // Listen for iCloud changes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            print("📲 iCloud data changed")
            Task {
                await conversationManager.loadConversation()
            }
        }
        
        // Listen for proactive messages
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ProactiveMessageAdded"),
            object: nil,
            queue: .main
        ) { notification in
            print("🤖 Proactive message received")
            Task {
                await conversationManager.loadConversation()
            }
        }
        
        // Request HealthKit authorization on app launch
        Task {
            if healthKitManager.isHealthKitAvailable {
                do {
                    _ = try await healthKitManager.requestAuthorization()
                } catch {
                    print("HealthKit authorization failed: \(error)")
                }
            }
        }
        
        // Check for API key migration
        checkForMigration()
    }
    
    private func checkForMigration() {
        // Check if user has old OpenAI key but no OpenRouter key
        let oldKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        let newKey = UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY")
        
        if let oldKey = oldKey, !oldKey.isEmpty, (newKey == nil || newKey!.isEmpty) {
            // User has old key but no new key - show migration alert
            showMigrationAlert = true
            
            // Clear the old key to avoid confusion
            UserDefaults.standard.removeObject(forKey: "OPENAI_API_KEY")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
