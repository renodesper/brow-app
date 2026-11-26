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

/// Turns a two-finger swipe on the trackpad into one step to the next or the previous screen.
///
/// A swipe moves at most one screen however far it goes, and a mostly vertical one moves none.
public struct SwipeTracker: Sendable {
    public enum Phase: Sendable {
        case began, changed, ended
    }

    /// How far the fingers travel, in points, before the screen changes.
    public static let threshold = 36.0

    private var horizontal = 0.0
    private var vertical = 0.0
    private var hasMoved = false

    public init() {}

    /// - Parameters:
    ///   - fingersX: How far the fingers moved right since the last event; negative when they move left.
    ///   - fingersY: How far they moved down.
    /// - Returns: 1 for the next screen (fingers moving left), -1 for the previous one, 0 for no change.
    public mutating func add(fingersX: Double, fingersY: Double, phase: Phase) -> Int {
        switch phase {
        case .began:
            horizontal = fingersX
            vertical = fingersY
            hasMoved = false
        case .changed:
            horizontal += fingersX
            vertical += fingersY
        case .ended:
            horizontal = 0
            vertical = 0
            hasMoved = false
            return 0
        }
        guard !hasMoved, abs(horizontal) >= Self.threshold, abs(horizontal) > 1.5 * abs(vertical) else { return 0 }
        hasMoved = true
        return horizontal < 0 ? 1 : -1
    }
}
