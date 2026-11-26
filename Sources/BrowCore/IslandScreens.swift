import Foundation

/// A feature's card in the open island.
public enum Widget: String, Codable, CaseIterable, Sendable {
    case calendar, pomodoro, keepAwake, usage
}

/// How many cards a screen of the open island holds, and how they are arranged.
public enum ScreenLayout: String, Codable, CaseIterable, Sendable {
    /// One card across the whole width.
    case one
    /// Two cards side by side.
    case two
    /// Four cards, two rows of two.
    case four

    public var slots: Int {
        switch self {
        case .one: 1
        case .two: 2
        case .four: 4
        }
    }

    public var rows: Int { self == .four ? 2 : 1 }
}

/// One screen of the open island. The owner swipes left and right between screens.
///
/// It always holds exactly one widget per slot of its layout, and each widget at most once, so the views never
/// have to cope with a gap or a duplicate.
public struct IslandScreen: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public private(set) var layout: ScreenLayout
    public private(set) var widgets: [Widget]

    public init(id: UUID = UUID(), layout: ScreenLayout, widgets: [Widget]) {
        self.id = id
        self.layout = layout
        self.widgets = widgets
        fit()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        layout = try container.decode(ScreenLayout.self, forKey: .layout)
        widgets = try container.decode([Widget].self, forKey: .widgets)
        fit()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layout, forKey: .layout)
        try container.encode(widgets, forKey: .widgets)
    }

    private enum CodingKeys: String, CodingKey {
        case id, layout, widgets
    }

    /// Changes the layout, keeping the widgets that still fit and filling new slots with unused ones.
    public mutating func setLayout(_ newLayout: ScreenLayout) {
        layout = newLayout
        fit()
    }

    /// Puts a widget in a slot. If it already sits in another slot, the two swap places.
    public mutating func setWidget(_ widget: Widget, at slot: Int) {
        guard widgets.indices.contains(slot) else { return }
        if let other = widgets.firstIndex(of: widget), other != slot {
            widgets[other] = widgets[slot]
        }
        widgets[slot] = widget
    }

    /// A short name, like "Calendar + Pomodoro" or "All four".
    public var title: String {
        if widgets.count == Widget.allCases.count { return "All four" }
        return widgets.map(\.title).joined(separator: " + ")
    }

    /// One widget per slot, each at most once: extras are dropped, gaps filled with the first unused widgets.
    private mutating func fit() {
        var unique: [Widget] = []
        for widget in widgets where !unique.contains(widget) {
            unique.append(widget)
        }
        unique = Array(unique.prefix(layout.slots))
        for widget in Widget.allCases where unique.count < layout.slots && !unique.contains(widget) {
            unique.append(widget)
        }
        widgets = unique
    }
}

extension Widget {
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .pomodoro: "Pomodoro"
        case .keepAwake: "Keep Awake"
        case .usage: "AI Usage"
        }
    }
}

/// The owner's list of screens, as saved in the preferences.
public enum IslandScreens {
    public static let maxCount = 5

    /// The screens a new install starts with: the calendar alone, the calendar with the pomodoro, and all four.
    public static var defaults: [IslandScreen] {
        [IslandScreen(layout: .one, widgets: [.calendar]),
         IslandScreen(layout: .two, widgets: [.calendar, .pomodoro]),
         IslandScreen(layout: .four, widgets: [.pomodoro, .keepAwake, .usage, .calendar])]
    }

    /// Saved screens, or the defaults if there are none or they can't be read.
    public static func decode(_ data: Data?) -> [IslandScreen] {
        guard let data, let screens = try? JSONDecoder().decode([IslandScreen].self, from: data),
              !screens.isEmpty else { return defaults }
        return Array(screens.prefix(maxCount))
    }

    public static func encode(_ screens: [IslandScreen]) -> Data? {
        try? JSONEncoder().encode(screens)
    }

    /// A new screen to add: the first layout-and-widget mix not on the list yet, so adding one shows a change.
    public static func newScreen(after screens: [IslandScreen]) -> IslandScreen {
        for widget in Widget.allCases where !screens.contains(where: { $0.widgets == [widget] }) {
            return IslandScreen(layout: .one, widgets: [widget])
        }
        return IslandScreen(layout: .two, widgets: [.pomodoro, .keepAwake])
    }
}

/// Follows a two-finger swipe on the trackpad: how far the current screen has been dragged, and at the end whether
/// the swipe moves one screen or springs back.
///
/// A swipe moves at most one screen however far it goes, a mostly vertical one moves none, and dragging toward a
/// side with no screen resists like a rubber band and never commits.
public struct SwipeTracker: Sendable {
    public enum Phase: Sendable {
        case began, changed, ended
    }

    public enum Outcome: Equatable, Sendable {
        /// Nothing to show: not a horizontal swipe, or none under way.
        case none
        /// The current screen is this far from rest, in points; negative is to the left.
        case drag(Double)
        /// The swipe is over and moves by this many screens: 1 for the next, -1 for the previous.
        case commit(Int)
        /// The swipe is over and the screen springs back.
        case cancel
    }

    /// How far the fingers travel, in points, before the swipe is read as horizontal or vertical.
    public static let lockDistance = 6.0
    /// The share of the island's width a swipe has to cover to move a screen by distance alone.
    public static let commitFraction = 0.25
    /// How fast, in points a second, a flick has to be at the end to move a screen however short it was.
    public static let flickSpeed = 500.0
    /// The least a flick has to travel, in points.
    public static let flickDistance = 12.0

    private enum Axis { case undecided, horizontal, vertical }

    private var horizontal = 0.0
    private var vertical = 0.0
    private var axis = Axis.undecided
    private var velocity = 0.0
    private var lastTime: Double?

    public init() {}

    /// - Parameters:
    ///   - fingersX: How far the fingers moved right since the last event; negative when they move left.
    ///   - fingersY: How far they moved down.
    ///   - time: When the event happened, in seconds, for the speed of a flick.
    ///   - canGoNext: Whether there is a screen after the current one.
    ///   - canGoPrevious: Whether there is a screen before it.
    ///   - width: The island's width in points, which the commit distance is a share of.
    public mutating func add(fingersX: Double, fingersY: Double, phase: Phase, time: Double = 0,
                             canGoNext: Bool = true, canGoPrevious: Bool = true, width: Double = 600) -> Outcome {
        switch phase {
        case .began:
            reset()
            horizontal = fingersX
            vertical = fingersY
            lastTime = time
            return decideAxis() ? .drag(offset(canGoNext, canGoPrevious, width)) : .none
        case .changed:
            horizontal += fingersX
            vertical += fingersY
            if let lastTime, time > lastTime { velocity = fingersX / (time - lastTime) }
            lastTime = time
            if axis == .undecided, !decideAxis() { return .none }
            guard axis == .horizontal else { return .none }
            return .drag(offset(canGoNext, canGoPrevious, width))
        case .ended:
            defer { reset() }
            guard axis == .horizontal else { return .none }
            let step = horizontal < 0 ? 1 : -1
            guard step == 1 ? canGoNext : canGoPrevious else { return .cancel }
            let farEnough = abs(horizontal) >= Self.commitFraction * width
            let flicked = abs(velocity) >= Self.flickSpeed && abs(horizontal) >= Self.flickDistance
                && (velocity < 0) == (horizontal < 0)
            return farEnough || flicked ? .commit(step) : .cancel
        }
    }

    private mutating func reset() {
        horizontal = 0
        vertical = 0
        axis = .undecided
        velocity = 0
        lastTime = nil
    }

    /// Reads the swipe as horizontal or vertical once it has gone far enough. Returns whether it is horizontal.
    private mutating func decideAxis() -> Bool {
        guard axis == .undecided else { return axis == .horizontal }
        guard max(abs(horizontal), abs(vertical)) >= Self.lockDistance else { return false }
        axis = abs(horizontal) > 1.5 * abs(vertical) ? .horizontal : .vertical
        return axis == .horizontal
    }

    private func offset(_ canGoNext: Bool, _ canGoPrevious: Bool, _ width: Double) -> Double {
        let hasScreen = horizontal < 0 ? canGoNext : canGoPrevious
        guard !hasScreen else { return horizontal }
        // Toward a side with nothing there it gives less and less, and never more than a fifth of the width.
        let limit = 0.2 * width
        let pull = abs(horizontal)
        let resisted = limit * pull / (pull + limit)
        return horizontal < 0 ? -resisted : resisted
    }
}
