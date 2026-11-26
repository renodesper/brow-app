import SwiftUI

/// The design's two typefaces: Manrope for numbers and titles, Inter for everything else. Both ship inside the app
/// (`Support/Fonts`, registered through `ATSApplicationFontsPath`), so a build run outside the bundle, like
/// `swift run`, quietly falls back to the system font.
///
/// The fonts are variable, and macOS names their weights after the PostScript instances listed below.
enum Typeface {
    /// Manrope, for big numbers, times and titles. The design uses 700 to 800.
    static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        let name = switch weight {
        case .heavy, .black: "Manrope-ExtraBold"
        case .bold: "Manrope-Bold"
        default: "Manrope-SemiBold"
        }
        return .custom(name, size: size)
    }

    /// Inter, for UI text.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
        return .custom(name, size: size)
    }
}
