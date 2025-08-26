//
//  SystemPromptLoader.swift
//  TrainerApp
//
//  Utility to load system prompt from file
//

import Foundation

struct SystemPromptLoader {
    static func loadSystemPrompt() -> String {
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