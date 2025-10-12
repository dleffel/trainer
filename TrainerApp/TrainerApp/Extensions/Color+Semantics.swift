import SwiftUI

// MARK: - Color Extensions

extension Color {
    // MARK: - Brand Colors
    static let brandPrimary = Color.accentColor
    static let brandGradientStart = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let brandGradientEnd = Color(red: 0.4, green: 0.2, blue: 1.0)
    
    // MARK: - Surfaces (iOS 15+ adaptive)
    static let surfacePrimary = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let surfaceTertiary = Color(.tertiarySystemBackground)
    
    // MARK: - Message Bubbles
    static let userBubbleGradientStart = Color.blue
    static let userBubbleGradientEnd = Color.blue.opacity(0.8)
    static let assistantBubble = Color(.secondarySystemBackground)
    
    // MARK: - Status Indicators
    static let workoutComplete = Color.green
    static let workoutPending = Color.orange
    static let workoutMissed = Color.red
    static let workoutRest = Color.gray
    
    // MARK: - Workout Status Gradients
    static let completeGradientStart = Color.green
    static let completeGradientEnd = Color.green.opacity(0.7)
    static let pendingGradientStart = Color.orange
    static let pendingGradientEnd = Color.orange.opacity(0.7)
    
    // MARK: - Surface Elevation (Legacy - kept for compatibility)
    static let surfaceBase = Color(.systemGray6)
    static let surfaceRaised = Color(.systemGray5)
    static let surfaceHighest = Color(.systemGray4)
    
    // MARK: - Selection
    static let selectionBackground = Color.accentColor.opacity(0.15)
    static let selectionBorder = Color.accentColor
    
    // MARK: - Interactive States
    static let cardPressed = Color.primary.opacity(0.05)
    static let cardHover = Color.primary.opacity(0.03)
}

// MARK: - View Extensions for Shadows

extension View {
    /// Apply a modern card shadow with configurable elevation
    /// - Parameter elevation: Shadow intensity (1.0 = default, higher = more prominent)
    func cardShadow(elevation: CGFloat = 1.0) -> some View {
        self.shadow(
            color: Color.black.opacity(0.08 * elevation),
            radius: 4 * elevation,
            x: 0,
            y: 2 * elevation
        )
    }
    
    /// Apply a button shadow for prominent interactive elements
    func buttonShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )
    }
    
    /// Apply a subtle inner shadow effect
    func innerShadow() -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                .blur(radius: 0.5)
        )
    }
}

// MARK: - Spacing Grid

extension CGFloat {
    // Spacing
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
    
    // Corner Radius Standards
    static let radiusTiny: CGFloat = 8
    static let radiusSmall: CGFloat = 12
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 20
    static let radiusXL: CGFloat = 24
}

// MARK: - Typography Hierarchy

extension Font {
    // Display
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    
    // Headlines
    static let h1 = Font.system(size: 24, weight: .bold)
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let h3 = Font.system(size: 17, weight: .semibold)
    
    // Body
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyRegular = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    // Utility
    static let labelBold = Font.system(size: 13, weight: .bold)
    static let captionRegular = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    
    // Legacy (kept for compatibility)
    static let sectionHeader = Font.title3.bold()
    static let subsectionTitle = Font.headline
    static let metadata = Font.subheadline
    static let caption = Font.caption
}

// MARK: - Gradient Helpers

extension LinearGradient {
    /// User message bubble gradient
    static let userBubble = LinearGradient(
        colors: [Color.userBubbleGradientStart, Color.userBubbleGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Complete status gradient
    static let completeStatus = LinearGradient(
        colors: [Color.completeGradientStart, Color.completeGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Pending status gradient
    static let pendingStatus = LinearGradient(
        colors: [Color.pendingGradientStart, Color.pendingGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Brand gradient
    static let brand = LinearGradient(
        colors: [Color.brandGradientStart, Color.brandGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}