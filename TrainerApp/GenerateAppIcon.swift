#!/usr/bin/env swift

import AppKit
import Foundation

// Generate app icons with rowing symbol on ocean blue background
func generateAppIcon(size: CGSize, filename: String) {
    // Create image with proper color space
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    
    guard let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        print("Failed to create context for \(filename)")
        return
    }
    
    let rect = CGRect(origin: .zero, size: size)
    
    // Draw ocean blue gradient background
    let colors = [
        CGColor(red: 0.0, green: 0.4, blue: 0.7, alpha: 1.0),  // Deep ocean blue
        CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1.0)   // Lighter ocean blue
    ] as CFArray
    
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size.height),
            end: CGPoint(x: size.width, y: 0),
            options: []
        )
    }
    
    // Add rowing figure symbol in white
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext
    
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size.width * 0.6, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "figure.rower", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        let symbolSize = symbol.size
        let symbolRect = NSRect(
            x: (size.width - symbolSize.width) / 2,
            y: (size.height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        
        NSColor.white.set()
        symbol.draw(in: symbolRect)
    }
    
    // Create CGImage and save as PNG
    if let cgImage = context.makeImage() {
        let nsImage = NSImage(cgImage: cgImage, size: size)
        if let tiffData = nsImage.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: filename))
            print("Generated: \(filename) (\(Int(size.width))x\(Int(size.height)))")
        }
    }
}

// Generate all required icon sizes
let iconSizes: [(size: CGSize, filename: String)] = [
    (CGSize(width: 1024, height: 1024), "icon_1024x1024.png"),
    (CGSize(width: 180, height: 180), "icon_180x180.png"),
    (CGSize(width: 120, height: 120), "icon_120x120.png"),
    (CGSize(width: 167, height: 167), "icon_167x167.png"),
    (CGSize(width: 152, height: 152), "icon_152x152.png"),
    (CGSize(width: 76, height: 76), "icon_76x76.png"),
    (CGSize(width: 40, height: 40), "icon_40x40.png"),
    (CGSize(width: 60, height: 60), "icon_60x60.png"),
    (CGSize(width: 58, height: 58), "icon_58x58.png"),
    (CGSize(width: 87, height: 87), "icon_87x87.png"),
    (CGSize(width: 80, height: 80), "icon_80x80.png"),
    (CGSize(width: 20, height: 20), "icon_20x20.png"),
    (CGSize(width: 29, height: 29), "icon_29x29.png"),
]

print("Generating app icons with proper format...")
for (size, filename) in iconSizes {
    generateAppIcon(size: size, filename: "TrainerApp/TrainerApp/Assets.xcassets/AppIcon.appiconset/\(filename)")
}
print("Done! All icons generated.")