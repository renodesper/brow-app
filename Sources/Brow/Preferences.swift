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

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openMode = OpenMode(rawValue: defaults.string(forKey: Key.openMode) ?? "") ?? .hover
        showsLiveActivities = defaults.bool(Key.showsLiveActivities, default: true)
        screens = IslandScreens.decode(defaults.data(forKey: Key.screens))
        opensOnLastScreen = defaults.bool(Key.opensOnLastScreen, default: false)
        lastScreen = defaults.integer(forKey: Key.lastScreen)
    }

    private enum Key {
        static let openMode = "island.openMode"
        static let showsLiveActivities = "island.showsLiveActivities"
        static let screens = "island.screens"
        static let opensOnLastScreen = "island.opensOnLastScreen"
        static let lastScreen = "island.lastScreen"
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
