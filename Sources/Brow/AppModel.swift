import Foundation
import BrowCore
import Observation
import SwiftUI

/// Everything the island shows, in one place. Each part is observable on its own, so a view redraws only for
/// the part it reads.
@MainActor
final class AppModel {
    let island: IslandState
    let preferences: IslandPreferences
    let keepAwake: KeepAwake
    let pomodoro: PomodoroModel
    let usage: UsageModel
    let calendar: CalendarModel
    /// The key combination that opens Settings from anywhere, as text, or nil when it could not be registered.
    var settingsShortcut: String?

    init() {
        island = IslandState()
        preferences = IslandPreferences()
        keepAwake = KeepAwake()
        pomodoro = PomodoroModel()
        usage = UsageModel()
        calendar = CalendarModel()
    }

    var mode: IslandMode {
        if island.isOpen { return .open }
        return island.peek == nil ? .closed : .peek
    }

    /// What rests beside the notch while the island is closed, as the owner's settings allow.
    var compact: CompactContent {
        guard preferences.showsLiveActivities else { return CompactContent() }
        return CompactContent(pomodoro: pomodoro.showsBesideNotch && pomodoro.timer.isActive,
                              event: calendar.near,
                              keepAwake: keepAwake.showsBesideNotch && keepAwake.isOn)
    }

    var hasCompactContent: Bool { compact.glyphs > 0 }

    /// The screen the open island shows. There is always at least one.
    var currentScreen: IslandScreen {
        let screens = preferences.screens
        guard !screens.isEmpty else { return IslandScreens.defaults[0] }
        return screens[min(max(island.screenIndex, 0), screens.count - 1)]
    }

    /// The island's size right now, shoulders included. The window and the drawing both take it from here.
    var islandSize: CGSize {
        IslandLayout.size(mode: mode, notch: island.notch, glyphs: compact.glyphs,
                          layout: currentScreen.layout, hasDots: preferences.screens.count > 1, peek: island.peek,
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
    /// Whether the last change of screen went forward, for the direction the cards slide in from.
    var movedForward = true
    /// How far the current screen has been dragged from rest by a swipe in progress, in points.
    var dragOffset: CGFloat = 0
    /// Whether fingers are on the trackpad moving the screen: it follows them with no animation of its own.
    var isDragging = false
    /// The notch's size, or a notch-sized area on a screen without one.
    var notch = CGSize(width: 180, height: 32)
    var hasPhysicalNotch = true
    /// Whether the pointer rests on the closed island, which then grows a little: it is about to open, or can be
    /// clicked open.
    var isAnticipating = false
    /// The battery as it was when the island last opened, for the header. Nil on a Mac without one.
    var battery: PowerSource.Battery?
}

/// The island's sizes, in points. The design was drawn at 1.25×, so its pixels are divided by 1.25 here.
enum IslandLayout {
    static let openWidth: CGFloat = 624
    /// The canvas draws the event peek 560 px wide and the "Focus done" peek 640 px; points are pixels / 1.25.
    static func peekWidth(for peek: Peek?) -> CGFloat {
        switch peek {
        case .phaseFinished: 512
        case .eventStarted, nil: 448
        }
    }
    static let peekContentHeight: CGFloat = 64
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 14
    static let dotsHeight: CGFloat = 22

    /// How long the pointer may be outside the island before it closes. Coming back within it keeps it open.
    static let closeGrace: Duration = .milliseconds(280)

    /// The one spring every change of the island's size or content follows, so the shape and the cards settle
    /// together.
    static let spring = Spring(duration: 0.35, bounce: 0.15)
    /// With Reduce Motion on, the island changes with a short fade instead of the spring.
    static let reducedDuration = 0.15

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: reducedDuration) : .spring(spring)
    }
    /// How long the spring takes to come to rest. The window must not shrink before then.
    static func settlingDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedDuration : spring.settlingDuration
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
            let rows = CGFloat(layout.rows)
            let cards = rows * rowHeight(for: layout) + (rows - 1) * spacing
            body = CGSize(width: max(openWidth, notch.width + 2 * wing(glyphs: 3)),
                          height: notch.height + spacing + cards + (hasDots ? dotsHeight : 4) + padding)
        }
        return CGSize(width: body.width + 2 * shoulder(for: mode), height: body.height)
    }
}
