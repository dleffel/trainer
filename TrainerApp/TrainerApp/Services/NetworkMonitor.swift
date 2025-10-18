import Foundation
import Network
import Combine

/// Monitors network connectivity status using Apple's Network framework
@MainActor
class NetworkMonitor: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    // MARK: - Private Properties
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.trainerapp.networkmonitor")
    
    // Singleton for app-wide access
    static let shared = NetworkMonitor()
    
    // MARK: - Initialization
    
    init() {
        setupMonitoring()
    }
    
    
    // MARK: - Public Methods
    
    /// Start monitoring network status
    func startMonitoring() {
        monitor.start(queue: queue)
        print("🌐 NetworkMonitor: Started monitoring network connectivity")
    }
    
    /// Stop monitoring network status
    func stopMonitoring() {
        monitor.cancel()
        print("🌐 NetworkMonitor: Stopped monitoring network connectivity")
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let previouslyConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.connectionType = self.getConnectionType(from: path)
                
                // Log connectivity changes
                if previouslyConnected != self.isConnected {
                    if self.isConnected {
                        print("🌐 NetworkMonitor: Connection restored (\(self.connectionType?.description ?? "unknown"))")
                    } else {
                        print("🌐 NetworkMonitor: Connection lost")
                    }
                }
            }
        }
    }
    
    private func getConnectionType(from path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return nil
        }
    }
}

// MARK: - NWInterface.InterfaceType Extension

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        @unknown default:
            return "Unknown"
        }
    }
}