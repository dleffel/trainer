import Foundation

/// Utility functions for tool processing
enum ToolUtilities {
    /// Parse date strings into Date objects
    /// CRITICAL: Uses UTC timezone to match storage layer (prevents DST/timezone issues)
    static func parseDate(_ dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            // Get the user's LOCAL date components (e.g., Nov 2 PST)
            let localCalendar = Calendar.current
            let localComponents = localCalendar.dateComponents([.year, .month, .day], from: Date.current)
            
            // Create a UTC midnight date for that local date
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            
            return utcCalendar.date(from: localComponents) ?? Date.current
        } else if dateString.lowercased() == "tomorrow" {
            // Same logic but add 1 day
            let localCalendar = Calendar.current
            let tomorrow = localCalendar.date(byAdding: .day, value: 1, to: Date.current)!
            let localComponents = localCalendar.dateComponents([.year, .month, .day], from: tomorrow)
            
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            
            return utcCalendar.date(from: localComponents) ?? tomorrow
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")  // CRITICAL: Must match storage key generation
            
            return formatter.date(from: dateString) ?? Date.current
        }
    }

    /// Format dates for display
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Format tool results for inclusion in conversation
    static func formatToolResults(_ results: [ToolProcessor.ToolCallResult]) -> String {
        var formattedResults: [String] = []

        for result in results {
            if result.success {
                formattedResults.append("Tool '\(result.toolName)' executed successfully:\n\(result.result)")
            } else {
                formattedResults.append("Tool '\(result.toolName)' failed: \(result.error ?? "Unknown error")")
            }
        }

        return formattedResults.joined(separator: "\n\n")
    }
}