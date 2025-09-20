//
//  SystemPromptLoader.swift
//  TrainerApp
//
//  Utility to load system prompt from file
//

import Foundation

struct SystemPromptLoader {
    /// Load base system prompt without schedule data (for compatibility)
    static func loadSystemPrompt() -> String {
        return loadBaseSystemPrompt()
    }
    
    /// Load system prompt with embedded schedule snapshot for optimization
    static func loadSystemPromptWithSchedule() -> String {
        let basePrompt = loadBaseSystemPrompt()
        let scheduleSnapshot = TrainingScheduleManager.shared.generateScheduleSnapshot()
        
        // Insert schedule snapshot after the main prompt but before tool definitions
        let insertionMarker = "## 14 │ AVAILABLE TOOLS"
        
        if let insertionPoint = basePrompt.range(of: insertionMarker) {
            let beforeTools = String(basePrompt[..<insertionPoint.lowerBound])
            let fromTools = String(basePrompt[insertionPoint.lowerBound...])
            
            return beforeTools + "\n" + scheduleSnapshot + "\n\n" + fromTools
        } else {
            // Fallback: append at end if marker not found
            return basePrompt + "\n\n" + scheduleSnapshot
        }
    }
    
    /// Load the base system prompt from file
    private static func loadBaseSystemPrompt() -> String {
        // First, try Bundle (for when file is added to Xcode project)
        if let bundleURL = Bundle.main.url(forResource: "SystemPrompt", withExtension: "md") {
            do {
                let content = try String(contentsOf: bundleURL, encoding: .utf8)
                print("✅ Loaded SystemPrompt.md from Bundle")
                return content
            } catch {
                print("❌ Error loading from Bundle: \(error)")
            }
        }
        
        // Try multiple possible paths for development
        let fileManager = FileManager.default
        let possiblePaths = [
            // Absolute path
            "/Users/danielleffel/repos/trainer/TrainerApp/TrainerApp/SystemPrompt.md",
            // Relative to current directory
            "\(fileManager.currentDirectoryPath)/TrainerApp/TrainerApp/SystemPrompt.md",
            "TrainerApp/TrainerApp/SystemPrompt.md",
            // Just in case we're in TrainerApp directory
            "TrainerApp/SystemPrompt.md"
        ]
        
        print("📁 Current directory: \(fileManager.currentDirectoryPath)")
        print("🔍 Searching for SystemPrompt.md in paths:")
        
        for path in possiblePaths {
            print("  - \(path)")
            if fileManager.fileExists(atPath: path) {
                do {
                    let content = try String(contentsOfFile: path, encoding: .utf8)
                    print("✅ Loaded SystemPrompt.md from: \(path)")
                    // Verify we got the rowing coach content
                    if content.contains("Rowing‑Coach GPT") {
                        print("✅ Verified: Found rowing coach content!")
                        return content
                    } else {
                        print("⚠️ Warning: File found but doesn't contain expected content")
                    }
                } catch {
                    print("❌ Error loading from \(path): \(error)")
                }
            }
        }
        
        // FATAL: Cannot load system prompt - this is an irrecoverable error
        fatalError("❌ FATAL ERROR: SystemPrompt.md not found! The app cannot function without the system prompt file.")
    }
}