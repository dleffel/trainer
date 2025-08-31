import SwiftUI
import BackgroundTasks

@main
struct TrainerAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Record app open for message suppression
                    ProactiveCoachManager.shared.recordAppOpen()
                }
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
