import Foundation

// MARK: - File-Based Store (Tier 3)

/// File-based storage for large datasets, logs, and archives
/// Use for: Data >1MB, logs with rotation, conversation history
final class FileStore<T: Codable>: PersistenceStore {
    typealias Value = T
    
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    /// Initialize a file-based store
    /// - Parameters:
    ///   - subdirectory: Subdirectory name in Documents (e.g., "APILogs")
    ///   - fileManager: FileManager instance (default: .default)
    /// - Throws: PersistenceError if directory creation fails
    init(subdirectory: String, fileManager: FileManager = .default) throws {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directory = documentsDir.appendingPathComponent(subdirectory)
        self.fileManager = fileManager
        
        // Configure encoder/decoder
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                print("📁 FileStore: Created directory at \(directory.path)")
            } catch {
                throw PersistenceError.fileSystemError("Failed to create directory: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - PersistenceStore Protocol
    
    func save(_ value: T, forKey key: String) throws {
        let fileURL = fileURL(for: key)
        
        do {
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            print("💾 FileStore: Saved '\(key)' (\(data.count) bytes)")
        } catch let error as EncodingError {
            throw PersistenceError.encodingFailed("FileStore: \(error.localizedDescription)")
        } catch {
            throw PersistenceError.saveFailed("FileStore: \(error.localizedDescription)")
        }
    }
    
    func load(forKey key: String) -> T? {
        let fileURL = fileURL(for: key)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let value = try decoder.decode(T.self, from: data)
            print("📥 FileStore: Loaded '\(key)' (\(data.count) bytes)")
            return value
        } catch {
            print("⚠️ FileStore: Failed to decode '\(key)': \(error.localizedDescription)")
            return nil
        }
    }
    
    func delete(forKey key: String) throws {
        let fileURL = fileURL(for: key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // File doesn't exist - not an error
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("🗑️ FileStore: Deleted '\(key)'")
        } catch {
            throw PersistenceError.deleteFailed("FileStore: \(error.localizedDescription)")
        }
    }
    
    func exists(forKey key: String) -> Bool {
        let fileURL = fileURL(for: key)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    func clear() throws {
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("🧹 FileStore: Cleared all files in \(directory.lastPathComponent)")
        } catch {
            throw PersistenceError.clearFailed("FileStore: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Additional File Operations
    
    /// List all file keys in the store
    func listKeys() -> [String] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
    
    /// Get file size for a specific key
    func fileSize(forKey key: String) -> Int? {
        let fileURL = fileURL(for: key)
        
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int else {
            return nil
        }
        
        return size
    }
    
    /// Get total size of all files in the store
    func totalSize() -> Int {
        let keys = listKeys()
        return keys.compactMap { fileSize(forKey: $0) }.reduce(0, +)
    }
    
    /// Archive (rename) a file with a timestamp
    func archive(key: String) throws {
        let fileURL = fileURL(for: key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.fileSystemError("File not found: \(key)")
        }
        
        let timestamp = DateFormatter().string(from: Date())
        let archiveName = "\(key)_\(timestamp)"
        let archiveURL = directory.appendingPathComponent("\(archiveName).json")
        
        do {
            try fileManager.moveItem(at: fileURL, to: archiveURL)
            print("📦 FileStore: Archived '\(key)' as '\(archiveName)'")
        } catch {
            throw PersistenceError.fileSystemError("Failed to archive: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func fileURL(for key: String) -> URL {
        // Ensure key has .json extension
        let fileName = key.hasSuffix(".json") ? key : "\(key).json"
        return directory.appendingPathComponent(fileName)
    }
}

// MARK: - Date-Keyed Extension

extension FileStore: DateKeyedStore {
    
    /// Generate a standardized date key (yyyy-MM-dd in UTC)
    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")  // CRITICAL: Always UTC
        return formatter.string(from: date)
    }
    
    /// Save a value for a specific date
    func save(_ value: T, for date: Date) throws {
        try save(value, forKey: dateKey(for: date))
    }
    
    /// Load a value for a specific date
    func load(for date: Date) -> T? {
        return load(forKey: dateKey(for: date))
    }
    
    /// Delete a value for a specific date
    func delete(for date: Date) throws {
        try delete(forKey: dateKey(for: date))
    }
    
    /// Clear a range of dates
    func clearRange(from startDate: Date, to endDate: Date) throws {
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate <= endDate {
            try? delete(for: currentDate)  // Ignore errors if file doesn't exist
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        print("🧹 FileStore: Cleared date range from \(dateKey(for: startDate)) to \(dateKey(for: endDate))")
    }
}