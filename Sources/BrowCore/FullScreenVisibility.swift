import CoreGraphics
import Foundation

/// Whether the island shows over an app in full screen.
public enum FullScreenMode: String, CaseIterable, Sendable {
    /// Hidden in full screen, alerts included.
    case never
    /// Hidden in full screen, except while a peek (a meeting starting, a session ending) is on screen.
    case alerts
    /// Shown over full-screen apps.
    case always

    /// Whether the island is on screen, given whether a full-screen app covers its display and whether it peeks.
    public func showsIsland(covered: Bool, peeking: Bool) -> Bool {
        guard covered else { return true }
        switch self {
        case .never: return false
        case .alerts: return peeking
        case .always: return true
        }
    }

    /// Whether the panel must be allowed into full-screen Spaces: only while it is meant to show there.
    public func needsFullScreenAuxiliary(peeking: Bool) -> Bool {
        switch self {
        case .never: return false
        case .alerts: return peeking
        case .always: return true
        }
    }
}

/// Tells from a list of on-screen windows whether an app in full screen covers a display.
///
/// A maximised window leaves the menu bar's strip free, so only a window of exactly the display's size counts.
public enum FullScreenDetection {
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        public var ownerName: String
        public var layer: Int
        public var bounds: CGRect
        public var alpha: Double

        public init(ownerPID: Int32, ownerName: String, layer: Int, bounds: CGRect, alpha: Double) {
            self.ownerPID = ownerPID
            self.ownerName = ownerName
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
        }
    }

    /// Owners whose display-sized windows are part of the system's own drawing, not an app in full screen.
    static let systemOwners: Set<String> = ["Dock", "Window Server", "WindowManager", "Control Center"]

    /// How far an edge may be off the expected one and still count as the same, in points. Window bounds are
    /// reported in whole points while the notch's inset is not (43.5 on a 14-inch MacBook Pro at one scaling),
    /// and a maximised window sits at least a point lower than a full-screen one, so this stays below 1.
    static let tolerance = 0.75

    /// `display` and the window bounds are in the same coordinate space, as `CGWindowListCopyWindowInfo` and
    /// `CGDisplayBounds` give them. `topInset` is the notch's height, zero on a display without one: an app in
    /// full screen on a notched display fills the area below it, not the strip beside the camera.
    public static func covers(display: CGRect, topInset: Double, windows: [Window], ignoring ownPID: Int32) -> Bool {
        let belowNotch = CGRect(x: display.minX, y: display.minY + topInset,
                                width: display.width, height: display.height - topInset)
        return windows.contains { window in
            window.ownerPID != ownPID
                && window.layer >= 0
                && window.alpha > 0
                && !systemOwners.contains(window.ownerName)
                && (isSame(window.bounds, display) || (topInset > 0 && isSame(window.bounds, belowNotch)))
        }
    }

    private static func isSame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
