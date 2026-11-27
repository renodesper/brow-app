import Foundation
import BrowCore
import Observation
import SwiftUI

/// Everything the island shows, in one place, shared by the island on every display. Each part is observable on
/// its own, so a view redraws only for the part it reads.
@MainActor
@Observable
final class AppModel {
    let preferences: IslandPreferences
    let keepAwake: KeepAwake
    let pomodoro: PomodoroModel
    let usage: UsageModel
    let calendar: CalendarModel
    /// The key combination that opens Settings from anywhere, as text, or nil when it could not be registered.
    var settingsShortcut: String?

    /// The notch's own size on this Mac (or the size the island takes on a display without one), for Settings.
    var detectedNotch = CGSize(width: 180, height: 32)

    init() {
        preferences = IslandPreferences()
        keepAwake = KeepAwake()
        pomodoro = PomodoroModel()
        usage = UsageModel()
        calendar = CalendarModel()
    }

    /// What rests beside the notch while the island is closed, as the owner's settings allow.
    var compact: CompactContent {
        guard preferences.showsLiveActivities else { return CompactContent() }
        return CompactContent(pomodoro: pomodoro.showsBesideNotch && pomodoro.timer.isActive,
                              event: calendar.near,
                              keepAwake: keepAwake.showsBesideNotch && keepAwake.isOn)
    }

    var hasCompactContent: Bool { compact.glyphs > 0 }

}

/// One display's island: the shared model, plus the state that belongs to this display alone (whether its island
/// is open, what it peeks, which screen it shows, how far a swipe has dragged it). Everything else reads through
/// to the shared model, so each display shows the same timers, events and settings.
@MainActor
@dynamicMemberLookup
final class DisplayContext {
    let app: AppModel
    let island = IslandState()

    init(app: AppModel) {
        self.app = app
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<AppModel, Value>) -> Value {
        app[keyPath: keyPath]
    }

    var mode: IslandMode {
        if island.isOpen { return .open }
        return island.peek == nil ? .closed : .peek
    }

    /// The screen the open island shows. There is always at least one.
    var currentScreen: IslandScreen {
        let screens = app.preferences.screens
        guard !screens.isEmpty else { return IslandScreens.defaults[0] }
        return screens[min(max(island.screenIndex, 0), screens.count - 1)]
    }

    /// The island's size right now, shoulders included. The window and the drawing both take it from here.
    var islandSize: CGSize {
        IslandLayout.size(mode: mode, notch: island.notch, glyphs: app.compact.glyphs,
                          layout: currentScreen.layout, hasDots: app.preferences.screens.count > 1, peek: island.peek,
                          anticipating: island.isAnticipating)
    }
}

enum IslandMode: Equatable {
    case closed, peek, open
}

/// A moment the island opens a little for by itself.
enum Peek: Equatable {
    case eventStarted(CalendarModel.Event)
    /// The phase that just ended.
    case phaseFinished(Pomodoro.Phase)
    /// A hello as the app starts: with no Dock or menu bar icon, it is the one sign that it is running.
    case hello
}

struct CompactContent {
    var pomodoro = false
    var event: CalendarModel.Event?
    var keepAwake = false

    var glyphs: Int { (pomodoro ? 1 : 0) + (event == nil ? 0 : 1) + (keepAwake ? 1 : 0) }
}

/// What the window and the views need to agree on.
@MainActor
@Observable
final class IslandState {
    var isOpen = false
    var peek: Peek?
    /// Which of the owner's screens the open island shows.
    var screenIndex = 0
    /// How far the current screen has been dragged from rest by a swipe in progress, in points.
    var dragOffset: CGFloat = 0
    /// Whether fingers are on the trackpad moving the screen: it follows them with no animation of its own.
    var isDragging = false
    /// The closed island's size: the notch's own, or the custom size the owner chose. A notch-sized area on a
    /// screen without one.
    var notch = CGSize(width: 180, height: 32)
    /// The notch's own size, whatever the custom size is.
    var detectedNotch = CGSize(width: 180, height: 32)
    var hasPhysicalNotch = true
    /// Whether the pointer rests on the closed island, which then grows a little: it is about to open, or can be
    /// clicked open.
    var isAnticipating = false
    /// Whether the island has shrunk away to nothing because an app is in full screen. The panel stays where it is;
    /// only the drawing goes, so the island can shrink and grow back as one smooth motion.
    var isTucked = false
}

/// The island's sizes, in points. The design was drawn at 1.25×, so its pixels are divided by 1.25 here.
enum IslandLayout {
    static let openWidth: CGFloat = 624
    /// The canvas draws the event peek 560 px wide and the "Focus done" peek 640 px; points are pixels / 1.25.
    static func peekWidth(for peek: Peek?) -> CGFloat {
        switch peek {
        case .phaseFinished: 512
        case .eventStarted, .hello, nil: 448
        }
    }
    static let peekContentHeight: CGFloat = 64
    static let spacing: CGFloat = 10
    /// The margin between the island's edge and its cards.
    static let sideMargin: CGFloat = 12
    static let padding: CGFloat = 14
    /// The page dots' row, from the cards to the island's bottom edge: the dots sit in the middle of it.
    static let dotsHeight: CGFloat = 28

    /// How long the pointer may be outside the island before it closes. Coming back within it keeps it open.
    static let closeGrace: Duration = .milliseconds(200)

    /// The spring every change of the island's size or content follows, so the shape and the cards settle
    /// together. Growing keeps a little bounce.
    static let spring = Spring(duration: 0.5, bounce: 0.12)
    /// Closing has no bounce: a shape that shrinks past its size and back looks like a stutter.
    static let closingSpring = Spring(duration: 0.55, bounce: 0)
    /// With Reduce Motion on, the island changes with a short fade instead of the spring.
    static let reducedDuration = 0.15

    static func animation(reduceMotion: Bool, closing: Bool = false) -> Animation {
        reduceMotion ? .easeOut(duration: reducedDuration) : .spring(closing ? closingSpring : spring)
    }
    /// How long the springs take to come to rest. The window must not shrink before then.
    static func settlingDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedDuration : max(spring.settlingDuration, closingSpring.settlingDuration)
    }
    /// Room beyond the island at the sides and below it while it animates, so a spring that overshoots is not
    /// cut off by the window. The top has none: the island hangs from the top of the screen.
    static let overshoot: CGFloat = 20

    /// Room on each side of the notch while something is going on; wider when several glyphs share it.
    static func wing(glyphs: Int) -> CGFloat {
        switch glyphs {
        case ...1: 64
        case 2: 76
        default: 92
        }
    }

    /// The gap between neighbouring screens while they slide: wider than the island's side margin, so the next
    /// screen is out of sight until a swipe brings it in.
    static let screenGap: CGFloat = 16

    /// The height of one screen's cards, all its rows.
    static func cardsHeight(for layout: ScreenLayout) -> CGFloat {
        let rows = CGFloat(layout.rows)
        return rows * rowHeight(for: layout) + (rows - 1) * spacing
    }

    /// The height of one row of cards. A screen with a single card gives it more room.
    static func rowHeight(for layout: ScreenLayout) -> CGFloat {
        layout == .one ? 192 : 164
    }

    /// How far the top corners flare out over the menu bar, like the inside of a rounded corner.
    static func shoulder(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .closed: 5
        case .peek: 6
        case .open: 8
        }
    }

    static func bottomRadius(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .closed: 11
        case .peek: 24
        case .open: 28
        }
    }

    /// How much a closed island grows while the pointer rests on it.
    static let anticipationGrowth = CGSize(width: 8, height: 2)

    static func size(mode: IslandMode, notch: CGSize, glyphs: Int, layout: ScreenLayout, hasDots: Bool,
                     peek: Peek? = nil, anticipating: Bool = false) -> CGSize {
        let body: CGSize
        switch mode {
        case .closed:
            let growth = anticipating ? anticipationGrowth : .zero
            body = CGSize(width: notch.width + (glyphs > 0 ? 2 * wing(glyphs: glyphs) : 0) + growth.width,
                          height: notch.height + growth.height)
        case .peek:
            body = CGSize(width: max(peekWidth(for: peek), notch.width + 2 * wing(glyphs: 1)),
                          height: notch.height + peekContentHeight + padding)
        case .open:
            let cards = cardsHeight(for: layout)
            body = CGSize(width: max(openWidth, notch.width + 2 * wing(glyphs: 3)),
                          height: notch.height + spacing + cards + (hasDots ? dotsHeight : 4 + padding))
        }
        return CGSize(width: body.width + 2 * shoulder(for: mode), height: body.height)
    }
}
