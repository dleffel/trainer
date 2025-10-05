import Foundation

/// Utility functions for tool processing
enum ToolUtilities {
    /// Parse date strings into Date objects
    /// CRITICAL: Uses UTC timezone to match storage layer (prevents DST/timezone issues)
    static func parseDate(_ dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            // Get local start of day (e.g., Nov 2 00:00 PST)
            let localStartOfDay = Calendar.current.startOfDay(for: Date.current)
            
            // Convert to UTC by getting the date that represents the same moment in UTC
            // This preserves the calendar day: Saturday in PST → Saturday in UTC storage
            let utcCalendar = Calendar(identifier: .gregorian)
            let utcComponents = utcCalendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: localStartOfDay)
            
            var utcCalendarForConstruction = Calendar(identifier: .gregorian)
            utcCalendarForConstruction.timeZone = TimeZone(identifier: "UTC")!
            
            return utcCalendarForConstruction.date(from: utcComponents) ?? localStartOfDay
        } else if dateString.lowercased() == "tomorrow" {
            // Get local start of tomorrow (local time)
            let localTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date.current)!
            let localStartOfTomorrow = Calendar.current.startOfDay(for: localTomorrow)
            
            // Convert to UTC preserving the calendar day
            let utcCalendar = Calendar(identifier: .gregorian)
            let utcComponents = utcCalendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: localStartOfTomorrow)
            
            var utcCalendarForConstruction = Calendar(identifier: .gregorian)
            utcCalendarForConstruction.timeZone = TimeZone(identifier: "UTC")!
            
            return utcCalendarForConstruction.date(from: utcComponents) ?? localStartOfTomorrow
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