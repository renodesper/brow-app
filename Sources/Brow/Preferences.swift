import Foundation
import BrowCore
import Observation

/// The island's own settings: how it opens, what rests beside the notch, and the screens of the open island.
/// Each feature keeps its own settings in its model. All of them are saved as they change.
@MainActor
@Observable
final class IslandPreferences {
    enum OpenMode: String, CaseIterable {
        /// Opens when the pointer rests on the notch, closes when it leaves.
        case hover
        /// Opens only on a click, and still closes when the pointer leaves.
        case click
    }

    var openMode: OpenMode {
        didSet { defaults.set(openMode.rawValue, forKey: Key.openMode) }
    }

    /// How long the pointer rests on the notch, in seconds, before the island opens.
    static let hoverDelayRange = 0.2...2.0
    static let defaultHoverDelay = 0.5

    var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) }
    }

    /// Whether the closed island is exactly the notch's size, or the custom size below.
    var matchesNotch: Bool {
        didSet { defaults.set(matchesNotch, forKey: Key.matchesNotch) }
    }

    /// The closed island's custom width and height in points, used when `matchesNotch` is off and never less than the
    /// notch. Zero until the owner first asks for a custom size.
    var customWidth: Double {
        didSet { defaults.set(customWidth, forKey: Key.customWidth) }
    }

    var customHeight: Double {
        didSet { defaults.set(customHeight, forKey: Key.customHeight) }
    }

    /// Whether the island opens a little to say hello as the app starts.
    var showsLaunchHello: Bool {
        didSet { defaults.set(showsLaunchHello, forKey: Key.showsLaunchHello) }
    }

    /// The master switch for everything beside the notch. Each feature also has its own.
    var showsLiveActivities: Bool {
        didSet { defaults.set(showsLiveActivities, forKey: Key.showsLiveActivities) }
    }

    var screens: [IslandScreen] {
        didSet { defaults.set(IslandScreens.encode(screens), forKey: Key.screens) }
    }

    /// Whether the island opens on the screen used last, rather than on the first one.
    var opensOnLastScreen: Bool {
        didSet { defaults.set(opensOnLastScreen, forKey: Key.opensOnLastScreen) }
    }

    var lastScreen: Int {
        didSet { defaults.set(lastScreen, forKey: Key.lastScreen) }
    }

    /// Whether a display without a notch keeps a small pill at the top while nothing runs, as something to point at.
    var showsPillWithoutNotch: Bool {
        didSet { defaults.set(showsPillWithoutNotch, forKey: Key.showsPillWithoutNotch) }
    }

    /// The displays the island is turned off on, by their stable identity. A display not listed shows it, so a
    /// newly connected one does too.
    var hiddenDisplays: Set<String> {
        didSet { defaults.set(hiddenDisplays.sorted(), forKey: Key.hiddenDisplays) }
    }

    func showsIsland(onDisplay id: String) -> Bool {
        !hiddenDisplays.contains(id)
    }

    func setShowsIsland(_ shows: Bool, onDisplay id: String) {
        if shows {
            hiddenDisplays.remove(id)
        } else {
            hiddenDisplays.insert(id)
        }
    }

    /// Whether the island shows over an app in full screen.
    var fullScreenMode: FullScreenMode {
        didSet { defaults.set(fullScreenMode.rawValue, forKey: Key.fullScreenMode) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openMode = OpenMode(rawValue: defaults.string(forKey: Key.openMode) ?? "") ?? .click
        let savedDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? Self.defaultHoverDelay
        hoverDelay = min(max(savedDelay, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        showsLaunchHello = defaults.bool(Key.showsLaunchHello, default: true)
        matchesNotch = defaults.bool(Key.matchesNotch, default: true)
        customWidth = defaults.double(forKey: Key.customWidth)
        customHeight = defaults.double(forKey: Key.customHeight)
        showsLiveActivities = defaults.bool(Key.showsLiveActivities, default: true)
        screens = IslandScreens.decode(defaults.data(forKey: Key.screens))
        opensOnLastScreen = defaults.bool(Key.opensOnLastScreen, default: false)
        lastScreen = defaults.integer(forKey: Key.lastScreen)
        hiddenDisplays = Set(defaults.stringArray(forKey: Key.hiddenDisplays) ?? [])
        showsPillWithoutNotch = defaults.bool(Key.showsPillWithoutNotch, default: true)
        fullScreenMode = FullScreenMode(rawValue: defaults.string(forKey: Key.fullScreenMode) ?? "") ?? .never
    }

    private enum Key {
        static let openMode = "island.openMode"
        static let showsLaunchHello = "island.showsLaunchHello"
        static let hoverDelay = "island.hoverDelay"
        static let matchesNotch = "island.matchesNotch"
        static let customWidth = "island.customWidth"
        static let customHeight = "island.customHeight"
        static let showsLiveActivities = "island.showsLiveActivities"
        static let screens = "island.screens"
        static let opensOnLastScreen = "island.opensOnLastScreen"
        static let lastScreen = "island.lastScreen"
        static let hiddenDisplays = "island.hiddenDisplays"
        static let showsPillWithoutNotch = "island.showsPillWithoutNotch"
        static let fullScreenMode = "island.fullScreenMode"
    }
}

extension UserDefaults {
    /// The saved value, or `fallback` if none was ever saved (where `bool(forKey:)` would say false).
    func bool(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }

    func int(_ key: String, default fallback: Int) -> Int {
        object(forKey: key) as? Int ?? fallback
    }
}
