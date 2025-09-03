import SwiftUI
import BackgroundTasks

// Navigation state for handling deep links
class NavigationState: ObservableObject {
    @Published var selectedTab = 0
    @Published var targetWorkoutDate: Date?
    @Published var showCalendar = false
    
    func navigateToWorkoutDay(date: Date) {
        targetWorkoutDate = date
        selectedTab = 1 // Calendar tab (assuming tab order: 0=Chat, 1=Calendar, 2=Settings)
        showCalendar = true
    }
}

@main
struct TrainerAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var navigationState = NavigationState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .onAppear {
                    // Record app open for message suppression
                    ProactiveCoachManager.shared.recordAppOpen()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // trainer://calendar/2024-01-15
        guard url.scheme == "trainer",
              url.host == "calendar",
              let dateString = url.pathComponents.last,
              !dateString.isEmpty else {
            print("⚠️ Invalid deep link URL: \(url)")
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        if let date = dateFormatter.date(from: dateString) {
            print("📱 Deep link: Navigating to workout day \(date)")
            navigationState.navigateToWorkoutDay(date: date)
        } else {
            print("⚠️ Failed to parse date from deep link: \(dateString)")
        }
    }
}

// App Delegate for handling background tasks
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Register background task handler FIRST before any async work
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.trainerapp.coachCheck",
            using: nil
        ) { task in
            // Handle the background task
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            
            // Let ProactiveCoachManager handle it
            Task {
                await ProactiveCoachManager.shared.handleBackgroundRefresh(refreshTask)
            }
        }
        
        print("✅ Background task handler registered")
        
        // Initialize proactive messaging asynchronously after launch
        DispatchQueue.main.async {
            Task {
                await ProactiveCoachManager.shared.initialize()
            }
        }
        
        return true
    }
}
