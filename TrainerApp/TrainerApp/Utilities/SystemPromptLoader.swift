import Foundation

/// Utility class for loading the system prompt from file
class SystemPromptLoader {
    static let shared = SystemPromptLoader()
    
    private init() {}
    
    /// Load system prompt from SystemPrompt.md file
    func loadSystemPrompt() -> String {
        // First try to load from the file system (for development)
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let systemPromptPath = "\(currentPath)/TrainerApp/TrainerApp/SystemPrompt.md"
        
        if fileManager.fileExists(atPath: systemPromptPath) {
            do {
                let content = try String(contentsOfFile: systemPromptPath, encoding: .utf8)
                print("Loaded SystemPrompt.md from file system")
                return content
            } catch {
                print("Error loading SystemPrompt.md from file system: \(error)")
            }
        }
        
        // Fall back to bundle (for production)
        if let url = Bundle.main.url(forResource: "SystemPrompt", withExtension: "md") {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                print("Loaded SystemPrompt.md from bundle")
                return content
            } catch {
                print("Error loading SystemPrompt.md from bundle: \(error)")
            }
        }
        
        print("SystemPrompt.md not found, using default prompt")
        return defaultSystemPrompt
    }
}