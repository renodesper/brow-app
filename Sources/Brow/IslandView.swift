import BrowCore
import SwiftUI

/// What the views can ask the window for.
struct IslandActions {
    var open: () -> Void
    var showScreen: (Int) -> Void
    var endPeek: () -> Void
}

/// The island: a black shape hanging from the top center of its window. It is the notch while closed, a short
/// banner while it peeks, and one screen of cards while open. Views are a pure function of the models; the only
/// animations are the change of size and the slide from one screen to the next.
struct IslandView: View {
    let model: DisplayContext
    let actions: IslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the island's content does as it comes and goes. The shape leads: content arrives a moment after it
    /// starts to grow, settling down from slightly small and blurred, and leaves quickly before the shape shrinks.
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let arrive = AnyTransition.opacity
            .combined(with: .scale(scale: 0.94, anchor: .top))
            .combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0)))
            .animation(.easeOut(duration: 0.26).delay(0.07))
        let leave = AnyTransition.opacity
            .combined(with: .scale(scale: 0.97, anchor: .top))
            .animation(.easeIn(duration: 0.12))
        return .asymmetric(insertion: arrive, removal: leave)
    }

    var body: some View {
        let island = model.island
        let mode = model.mode
        let size = model.islandSize
        let shoulder = IslandLayout.shoulder(for: mode)
        let shape = IslandShape(shoulder: shoulder, bottomRadius: IslandLayout.bottomRadius(for: mode))
        // On a screen without a notch there is nothing to blend into, so the island hides while it has
        // nothing to show, unless the owner wants a small pill there to point at.
        let isIdlePill = !island.hasPhysicalNotch && mode == .closed && !model.hasCompactContent
            && model.preferences.showsPillWithoutNotch
        let isVisible = island.hasPhysicalNotch || mode != .closed || model.hasCompactContent || isIdlePill

        ZStack(alignment: .top) {
            switch mode {
            case .open:
                OpenIsland(model: model, actions: actions).transition(contentTransition)
            case .peek:
                if let peek = island.peek {
                    PeekView(peek: peek, model: model, actions: actions).transition(contentTransition)
                }
            case .closed:
                if model.hasCompactContent {
                    CompactIsland(model: model).transition(.opacity)
                }
            }
        }
        .padding(.horizontal, shoulder)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The window sits in the screen's unsafe area on purpose: the notch is the whole point.
        .ignoresSafeArea()
        .animation(IslandLayout.animation(reduceMotion: reduceMotion), value: mode)
        .animation(IslandLayout.animation(reduceMotion: reduceMotion), value: size)
        .environment(\.colorScheme, .dark)
    }
}

/// A blur for a transition to fade through.
private struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

/// The island's outline: flat along the top of the screen, its top corners flaring outward over the menu bar
/// like the inside of a rounded corner, and rounded at the bottom.
struct IslandShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set {
            shoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(min(shoulder, rect.height / 2, rect.width / 4), 0)
        let r = max(min(bottomRadius, (rect.width - 2 * s) / 2, rect.height - s), 0)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.minY + s),
                          control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                          control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The design's colors: one accent per feature, on black.
enum Palette {
    /// Pomodoro focus, and a usage limit past 80%. systemOrange, dark.
    static let orange = Color(rgb: 0xFF9F0A)
    /// Pomodoro breaks. systemGreen, dark.
    static let green = Color(rgb: 0x30D158)
    /// Keep Awake. systemCyan, dark.
    static let cyan = Color(rgb: 0x64D2FF)
    /// AI Usage title and bars. systemPurple, dark.
    static let purple = Color(rgb: 0xBF5AF2)
    /// The Calendar card's title. systemRed, dark.
    static let red = Color(rgb: 0xFF453A)
    /// The "in 12m" chip on the next event. systemBlue, dark.
    static let blue = Color(rgb: 0x0A84FF)
    static let card = Color(rgb: 0x1C1C1E)
    static let secondary = Color.white.opacity(0.6)
    static let track = Color.white.opacity(0.12)
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

/// What rests beside the notch while the island is closed: what is going on to the left of the camera, and
/// the time that matters most to the right.
private struct CompactIsland: View {
    let model: DisplayContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compact = model.compact
        let wing = IslandLayout.wing(glyphs: compact.glyphs)
        // A glyph grows in from half size and shrinks away, so the wings don't just snap wider.
        let glyphTransition: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity)
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if compact.pomodoro {
                    PomodoroRing(pomodoro: model.pomodoro, lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                        .transition(glyphTransition)
                }
                if let event = compact.event {
                    CalendarGlyph(color: event.color, size: 19)
                        .transition(glyphTransition)
                }
                if compact.keepAwake {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                        .transition(glyphTransition)
                }
            }
            .padding(.leading, 12)
            .frame(width: wing, alignment: .leading)

            Color.clear.frame(width: model.island.notch.width)

            Group {
                // One time fits. An event about to start matters most, then a running pomodoro, then Keep Awake.
                if let event = compact.event {
                    EventCountdown(event: event, showsDot: true)
                } else if compact.pomodoro {
                    Countdown(pomodoro: model.pomodoro).foregroundStyle(.white)
                } else if compact.keepAwake {
                    KeepAwakeRemaining(keepAwake: model.keepAwake)
                }
            }
            .padding(.trailing, 12)
            .frame(width: wing, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .bold).monospacedDigit())
        .monospacedDigit()
        .lineLimit(1)
        .frame(height: model.island.notch.height)
    }
}

/// The open island: the date beside the camera, one screen of cards, and dots for the other screens.
private struct OpenIsland: View {
    let model: DisplayContext
    let actions: IslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let island = model.island
        let screens = model.preferences.screens
        let screen = model.currentScreen
        let index = min(max(island.screenIndex, 0), screens.count - 1)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                Spacer(minLength: island.notch.width + 16)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: island.notch.height)

            ScreenView(screen: screen, model: model)
                .id(screen.id)
                .transition(reduceMotion ? .opacity : .push(from: island.movedForward ? .trailing : .leading))
                .padding(.top, IslandLayout.spacing)
                .padding(.horizontal, 12)
                // Follows the fingers with no animation of its own; when they lift it springs back or carries on
                // with the change of screen.
                .offset(x: island.dragOffset)
                .animation(island.isDragging ? nil : IslandLayout.animation(reduceMotion: reduceMotion),
                           value: island.dragOffset)
                // No clip of its own: the island's shape clips it, and a rectangular clip here made a card dragged
                // partly out of view lose its background or its bottom.
                .frame(maxWidth: .infinity)

            if screens.count > 1 {
                HStack(spacing: 0) {
                    ForEach(screens.indices, id: \.self) { dot in
                        Button { actions.showScreen(dot) } label: {
                            Capsule()
                                .fill(dot == index ? Color.white : Color.white.opacity(0.32))
                                .frame(width: dot == index ? 12 : 6, height: 6)
                                .frame(width: 16, height: IslandLayout.dotsHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Screen \(dot + 1): \(screens[dot].title)")
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .animation(IslandLayout.animation(reduceMotion: reduceMotion), value: island.screenIndex)
    }
}

/// One screen's cards, in its layout's rows.
private struct ScreenView: View {
    let screen: IslandScreen
    let model: DisplayContext

    var body: some View {
        let layout = screen.layout
        let perRow = layout == .one ? 1 : 2
        VStack(spacing: IslandLayout.spacing) {
            ForEach(0..<layout.rows, id: \.self) { row in
                HStack(spacing: IslandLayout.spacing) {
                    ForEach(Array(screen.widgets.dropFirst(row * perRow).prefix(perRow)), id: \.self) { widget in
                        WidgetCard(widget: widget, model: model, isWide: layout == .one)
                    }
                }
                .frame(height: IslandLayout.rowHeight(for: layout))
            }
        }
    }
}

private struct WidgetCard: View {
    let widget: BrowCore.Widget
    let model: DisplayContext
    let isWide: Bool

    var body: some View {
        switch widget {
        case .calendar:
            if isWide {
                CalendarWideCard(calendar: model.calendar)
            } else {
                CalendarCard(calendar: model.calendar)
            }
        case .pomodoro:
            PomodoroCard(pomodoro: model.pomodoro)
        case .keepAwake:
            KeepAwakeCard(keepAwake: model.keepAwake)
        case .usage:
            UsageCard(usage: model.usage)
        }
    }
}

/// The island opening a little by itself: an event starting, or a pomodoro phase ending.
private struct PeekView: View {
    let peek: Peek
    let model: DisplayContext
    let actions: IslandActions

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.island.notch.height)
            HStack(spacing: 14) {
                switch peek {
                case .eventStarted(let event):
                    CalendarGlyph(color: event.color, size: 38)
                    titles(event.title, "\(timeRange(event)) · \(event.calendarTitle)")
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Circle().fill(event.color).frame(width: 8, height: 8)
                        Text("Now")
                    }
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    if let url = event.meetingURL { JoinButton(url: url, isProminent: true) }
                case .phaseFinished(let phase):
                    phaseFinished(phase)
                case .hello:
                    hello
                }
            }
            .padding(.horizontal, 18)
            .frame(height: IslandLayout.peekContentHeight)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture { actions.open() }
    }

    @ViewBuilder
    private var hello: some View {
        Image(systemName: "hand.wave.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Palette.cyan)
            .frame(width: 38, height: 38)
            .background(Palette.cyan.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        titles("Brow is running",
               model.preferences.openMode == .hover ? "Rest the pointer on the notch to open it." : "Click the notch to open it.")
        Spacer(minLength: 8)
    }

    @ViewBuilder
    private func phaseFinished(_ ended: Pomodoro.Phase) -> some View {
        let pomodoro = model.pomodoro
        let timer = pomodoro.timer
        let next = timer.phase
        let nextMinutes = Int(timer.settings.length(of: next) / 60)
        Image(systemName: ended == .focus ? "checkmark" : "cup.and.saucer.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(ended == .focus ? Palette.orange : Palette.green)
            .frame(width: 38, height: 38)
            .background((ended == .focus ? Palette.orange : Palette.green).opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        if ended == .focus {
            titles("Focus done", timer.isRunning
                   ? "Round \(timer.currentRound) of \(timer.settings.roundsUntilLongBreak) · break started"
                   : "Round \(timer.currentRound) of \(timer.settings.roundsUntilLongBreak) · next: \(nextMinutes) minute break")
        } else {
            titles("Break over", timer.isRunning ? "Focus started" : "Next: \(nextMinutes) minutes of focus")
        }
        Spacer(minLength: 8)
        HStack(spacing: 8) {
            if next == .focus {
                if !timer.isRunning {
                    Button("Later") { actions.endPeek() }
                        .buttonStyle(PillButtonStyle())
                    Button("Start Focus") {
                        pomodoro.toggle()
                        actions.endPeek()
                    }
                    .buttonStyle(PillButtonStyle(isPrimary: true, tint: Palette.orange))
                }
            } else {
                Button("Skip Break") {
                    pomodoro.skip()
                    actions.endPeek()
                }
                .buttonStyle(PillButtonStyle())
                if !timer.isRunning {
                    Button("Start Break") {
                        pomodoro.toggle()
                        actions.endPeek()
                    }
                    .buttonStyle(PillButtonStyle(isPrimary: true, tint: Palette.orange))
                }
            }
        }
    }

    private func titles(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .lineLimit(1)
    }

    private func timeRange(_ event: CalendarModel.Event) -> String {
        "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// A calendar glyph on a rounded square of the calendar's own color.
struct CalendarGlyph: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: "calendar")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A ring that fills as the pomodoro phase goes. It redraws every few seconds, only while a phase runs.
struct PomodoroRing: View {
    let pomodoro: PomodoroModel
    var lineWidth: CGFloat = 3

    var body: some View {
        let timer = pomodoro.timer
        let tint = timer.phase.tint
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 5 : 3600)) { context in
            let length = max(timer.settings.length(of: timer.phase), 1)
            let done = 1 - timer.remaining(at: context.date) / length
            ZStack {
                Circle().stroke(tint.opacity(0.28), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(done, 0.02))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// The time left in the pomodoro phase. It redraws once a second, only while a phase runs and only while it
/// is on screen; paused or waiting, it is plain text that never redraws.
struct Countdown: View {
    let pomodoro: PomodoroModel

    var body: some View {
        let timer = pomodoro.timer
        if let end = timer.endDate {
            // Ticks counted back from the end, so the display changes on the second the time does.
            let firstTick = end.addingTimeInterval(-timer.remaining(at: Date()).rounded(.up))
            TimelineView(.periodic(from: firstTick, by: 1)) { context in
                Text(Pomodoro.clockText(timer.remaining(at: context.date)))
            }
        } else {
            Text(Pomodoro.clockText(timer.remaining(at: Date())))
        }
    }
}

/// The minutes until an event starts, then "Now". It redraws once a minute, on the minute the number changes,
/// and only while it is on screen.
struct EventCountdown: View {
    let event: CalendarModel.Event
    var showsDot = false

    var body: some View {
        // Any whole number of minutes before the start lines the ticks up with the changes of the number.
        TimelineView(.periodic(from: event.start.addingTimeInterval(-24 * 60 * 60), by: 60)) { context in
            let text = Agenda.countdownText(to: event.start, at: context.date)
            if event.start <= context.date, showsDot {
                HStack(spacing: 5) {
                    Circle().fill(event.color).frame(width: 6, height: 6)
                    Text(text).foregroundStyle(.white)
                }
            } else {
                Text(text).foregroundStyle(event.color)
            }
        }
    }
}

/// Keep Awake's time left, like "52m" or "1h 20m", or "On" without an end. Redraws once a minute.
struct KeepAwakeRemaining: View {
    let keepAwake: KeepAwake

    var body: some View {
        if let until = keepAwake.until {
            TimelineView(.periodic(from: until.addingTimeInterval(-24 * 60 * 60), by: 60)) { context in
                Text(Self.text(until.timeIntervalSince(context.date)))
            }
        } else {
            Text("On")
        }
    }

    static func text(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded(.up)), 0)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

extension Pomodoro.Phase {
    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var tint: Color {
        switch self {
        case .focus: Palette.orange
        case .shortBreak, .longBreak: Palette.green
        }
    }
}
