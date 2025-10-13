import SwiftUI

// MARK: - Link Detecting Text

/// A view that detects and makes custom links (trainer://) tappable within text content.
/// Parses text for trainer:// URLs and renders them as interactive links.
struct LinkDetectingText: View {
    let text: String
    let isUser: Bool
    let onTap: (URL) -> Void
    
    var body: some View {
        let components = parseTextForLinks(text)
        
        if components.count == 1 && !components[0].isLink {
            // No links found, just show plain text
            Text(text)
        } else {
            // Build text with tappable links using AttributedString directly
            components.reduce(Text("")) { result, component in
                if component.isLink, let url = URL(string: component.text) {
                    // Create AttributedString directly and apply .link attribute
                    let label = getLinkDisplayText(from: component.text)
                    var attributed = AttributedString(label)
                    attributed.link = url
                    attributed.foregroundColor = isUser ? .white : .blue
                    attributed.underlineStyle = .single
                    
                    return result + Text(attributed)
                } else {
                    return result + Text(component.text)
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                // Only intercept trainer:// URLs for custom handling
                // All other URLs use default system behavior to preserve accessibility and system features
                if url.scheme == "trainer" {
                    print("🔗 Custom scheme URL intercepted: \(url.absoluteString)")
                    onTap(url)
                    return .handled
                } else {
                    print("🔗 Using default handler for URL: \(url.absoluteString)")
                    return .systemAction
                }
            })
        }
    }
    
    // MARK: - Private Helpers
    
    private func getLinkDisplayText(from urlString: String) -> String {
        if urlString.starts(with: "trainer://calendar/") {
            return "📋 View instructions"
        }
        return "Link"
    }
    
    private func parseTextForLinks(_ text: String) -> [(text: String, isLink: Bool)] {
        var components: [(text: String, isLink: Bool)] = []
        
        // Pattern to match trainer:// URLs, excluding trailing punctuation
        // Matches trainer:// followed by any non-whitespace except common punctuation
        let pattern = #"trainer://[^\s.,;:()!\[\]]+"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var lastEndIndex = 0
            
            for match in matches {
                // Add text before the link
                if match.range.location > lastEndIndex {
                    let beforeText = nsString.substring(with: NSRange(location: lastEndIndex, length: match.range.location - lastEndIndex))
                    if !beforeText.isEmpty {
                        components.append((text: beforeText, isLink: false))
                    }
                }
                
                // Add the link
                let linkText = nsString.substring(with: match.range)
                components.append((text: linkText, isLink: true))
                
                lastEndIndex = match.range.location + match.range.length
            }
            
            // Add any remaining text after the last link
            if lastEndIndex < nsString.length {
                let remainingText = nsString.substring(from: lastEndIndex)
                if !remainingText.isEmpty {
                    components.append((text: remainingText, isLink: false))
                }
            }
            
        } catch {
            // If regex fails, just return the whole text as non-link
            components.append((text: text, isLink: false))
        }
        
        return components
    }
}