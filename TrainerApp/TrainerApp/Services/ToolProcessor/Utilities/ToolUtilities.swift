import Foundation

/// Utility functions for tool processing
enum ToolUtilities {
    /// Parse date strings into Date objects
    static func parseDate(_ dateString: String) -> Date {
        if dateString.lowercased() == "today" {
            return Date.current
        } else if dateString.lowercased() == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date.current)!
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
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