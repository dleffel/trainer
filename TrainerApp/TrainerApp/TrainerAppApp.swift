import SwiftUI

// Navigation state for handling deep links
class NavigationState: ObservableObject {
    @Published var selectedTab = 0
    @Published var targetWorkoutDate: Date?
    
    func navigateToWorkoutDay(date: Date) {
        targetWorkoutDate = date
        selectedTab = 1 // Log tab (tab order: 0=Chat, 1=Log)
    }
}

@main
struct TrainerAppApp: App {
    @StateObject private var navigationState = NavigationState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
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
