import Foundation

/// The size of the closed island when the owner picks one instead of the notch's own.
///
/// A custom size is never smaller than the notch, widths are whole even points so half of every width is whole and all
/// frames share one center, and heights are whole points.
public enum NotchSizing {
    /// How much wider than the notch the custom width can go, in points.
    public static let extraWidth = 135.0
    /// How much taller than the notch the custom height can go, in points.
    public static let extraHeight = 12.0

    /// The size to use: the notch's, or the custom one where there is one, kept to at least the notch.
    public static func resolved(detectedWidth: Double, detectedHeight: Double,
                                customWidth: Double?, customHeight: Double?) -> (width: Double, height: Double) {
        let width = max(customWidth ?? detectedWidth, detectedWidth)
        let height = max(customHeight ?? detectedHeight, detectedHeight)
        return ((width / 2).rounded(.up) * 2, height.rounded(.up))
    }

    /// Where a custom size starts when the owner first asks for one: a little more than the notch.
    public static func starting(detectedWidth: Double, detectedHeight: Double) -> (width: Double, height: Double) {
        (detectedWidth + 15, detectedHeight + 2)
    }
}
