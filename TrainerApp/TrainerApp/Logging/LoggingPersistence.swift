import Foundation

/// Handles persistence of API logs to JSON files with rotation and archiving
final class LoggingPersistence {
    private let maxLogsPerFile = 1000
    private let maxRetentionDays = 30
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.trainerapp.logging.persistence", qos: .background)
    
    private var logsDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logsDir = documentsDirectory.appendingPathComponent("APILogs")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir
    }
    
    private var activeLogFileURL: URL {
        logsDirectory.appendingPathComponent("api_logs.json")
    }
    
    private var metadataFileURL: URL {
        logsDirectory.appendingPathComponent("api_logs_metadata.json")
    }
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Perform initial cleanup
        queue.async { [weak self] in
            self?.cleanupOldLogs()
        }
    }
    
    /// Append a new log entry
    func append(_ logEntry: APILogEntry) {
        queue.sync {
            var logs = loadLogsFromFile(activeLogFileURL)
            logs.append(logEntry)
            
            // Check if we need to rotate
            if logs.count >= maxLogsPerFile {
                archiveCurrentLogs(logs)
                logs = [logEntry] // Start fresh with just the new entry
            }
            
            // Save to active file
            saveLogsToFile(logs, url: activeLogFileURL)
            
            // Update metadata
            updateMetadata()
        }
    }
    
    /// Load all logs (active + archived)
    func loadAll() -> [APILogEntry] {
        var allLogs: [APILogEntry] = []
        
        // Load active logs
        allLogs.append(contentsOf: loadLogsFromFile(activeLogFileURL))
        
        // Load archived logs
        if let archivedFiles = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ) {
            let archiveFiles = archivedFiles.filter { url in
                url.lastPathComponent.hasPrefix("api_logs_") &&
                url.lastPathComponent.hasSuffix(".json") &&
                url.lastPathComponent != "api_logs.json" &&
                url.lastPathComponent != "api_logs_metadata.json"
            }
            
            for archiveFile in archiveFiles.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                allLogs.append(contentsOf: loadLogsFromFile(archiveFile))
            }
        }
        
        return allLogs
    }
    
    /// Clear all logs
    func clearAll() {
        queue.sync {
            // Remove all files in logs directory
            if let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            }
            
            // Update metadata
            updateMetadata()
        }
    }
    
    /// Load logs from a specific file
    private func loadLogsFromFile(_ url: URL) -> [APILogEntry] {
        guard let data = try? Data(contentsOf: url),
              let logs = try? decoder.decode([APILogEntry].self, from: data) else {
            return []
        }
        return logs
    }
    
    /// Save logs to a specific file
    private func saveLogsToFile(_ logs: [APILogEntry], url: URL) {
        guard let data = try? encoder.encode(logs) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    /// Archive current logs to a dated file
    private func archiveCurrentLogs(_ logs: [APILogEntry]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        
        let archiveURL = logsDirectory.appendingPathComponent("api_logs_\(dateString).json")
        saveLogsToFile(logs, url: archiveURL)
        
        // Compression can be added later if needed
    }
    
    /// Clean up old logs based on retention policy
    private func cleanupOldLogs() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxRetentionDays, to: Date()) ?? Date()
        
        if let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files {
                if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attributes.creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    /// Update metadata file with current state
    private func updateMetadata() {
        struct Metadata: Codable {
            let totalLogs: Int
            let oldestLogDate: Date?
            let newestLogDate: Date?
            let lastUpdated: Date
            let archiveCount: Int
        }
        
        let allLogs = loadAll()
        let sorted = allLogs.sorted { $0.timestamp < $1.timestamp }
        
        let archiveCount = (try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("api_logs_") && 
                     $0.lastPathComponent != "api_logs.json" && 
                     $0.lastPathComponent != "api_logs_metadata.json" }
            .count ?? 0
        
        let metadata = Metadata(
            totalLogs: allLogs.count,
            oldestLogDate: sorted.first?.timestamp,
            newestLogDate: sorted.last?.timestamp,
            lastUpdated: Date(),
            archiveCount: archiveCount
        )
        
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: metadataFileURL, options: .atomic)
        }
    }
}