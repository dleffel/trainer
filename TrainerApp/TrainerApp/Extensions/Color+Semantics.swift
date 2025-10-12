import SwiftUI

extension Color {
    // MARK: - Status Indicators
    static let workoutComplete = Color.green
    static let workoutPending = Color.orange
    static let workoutMissed = Color.red
    static let workoutRest = Color.gray
    
    // MARK: - Surface Elevation
    static let surfaceBase = Color(.systemGray6)
    static let surfaceRaised = Color(.systemGray5)
    static let surfaceHighest = Color(.systemGray4)
    
    // MARK: - Selection
    static let selectionBackground = Color.accentColor.opacity(0.15)
    static let selectionBorder = Color.accentColor
    
    // MARK: - Dark Mode Optimization
    // Note: For adaptive opacity in Views, use @Environment(\.colorScheme) instead
    // This is kept for reference but should not be used in practice
    // Example in View:
    // @Environment(\.colorScheme) var colorScheme
    // let opacity = colorScheme == .dark ? value * 1.5 : value
}

// MARK: - Spacing Grid
extension CGFloat {
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

// MARK: - Typography Hierarchy
extension Font {
    static let sectionHeader = Font.title3.bold()
    static let subsectionTitle = Font.headline
    static let metadata = Font.subheadline
    static let caption = Font.caption
}