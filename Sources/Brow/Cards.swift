import BrowCore
import SwiftUI

/// The frame every feature's card shares: a glyph and a sentence-case title in the feature's colour, something on
/// the right of it, and the card's content below.
private struct Card<Accessory: View, Content: View>: View {
    private let title: String
    private let symbol: String
    private let tint: Color
    private let accessory: Accessory
    private let content: Content

    init(_ title: String, symbol: String, tint: Color, @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
                accessory
            }
            .frame(height: 22)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// A capsule button: solid for the main action (white, or `tint`), a faint fill otherwise, or `tint` at a low
/// strength when `isTinted`. Its fill is its hit area.
struct PillButtonStyle: ButtonStyle {
    var isPrimary = false
    var isTinted = false
    /// The feature's colour: the solid fill of a primary button, the colour of a tinted one (cyan if not given).
    var tint: Color?
    var height: CGFloat = 28
    /// Whether it stretches to share a row equally with its neighbours.
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let accent = tint ?? Palette.cyan
        let fill: Color = isPrimary ? tint ?? .white : isTinted ? accent.opacity(0.22) : Palette.track
        let text: Color = isPrimary ? .black : isTinted ? accent : .white
        configuration.label
            .font(.system(size: height < 28 ? 11 : 12, weight: .semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, fillsWidth ? 4 : height < 28 ? 10 : 13)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: height)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed, litByHover: !isPrimary))
    }
}

/// A round button holding one glyph: neutral, or tinted by its feature.
private struct IconButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint ?? .white)
            .frame(width: 32, height: 32)
            .background((tint?.opacity(0.22) ?? Palette.track).opacity(configuration.isPressed ? 0.6 : 1), in: Circle())
            .contentShape(Circle())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// How a pressable control feels: it shrinks a little under the finger and lights up under the pointer. The
/// white main button doesn't light up, since there is nothing brighter than white.
private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    var litByHover = true
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .brightness(litByHover && isHovering ? 0.12 : 0)
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// A small tinted label, like "Focus · 2 of 4".
private struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

/// A thin bar, filled from the left.
private struct Bar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(tint).frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct PomodoroCard: View {
    let pomodoro: PomodoroModel

    var body: some View {
        let timer = pomodoro.timer
        let tint = timer.phase.tint
        Card("Pomodoro", symbol: "timer", tint: tint) {
            Chip(text: "\(timer.phase.title) · \(timer.currentRound) of \(timer.settings.roundsUntilLongBreak)",
                 tint: tint)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Countdown(pomodoro: pomodoro)
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .tracking(-0.5)
                    .monospacedDigit()
                Text("of \(Pomodoro.clockText(timer.settings.length(of: timer.phase)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
            PomodoroProgress(pomodoro: pomodoro)
            HStack(spacing: 6) {
                Button { pomodoro.toggle() } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .animation(.snappy(duration: 0.2), value: timer.isRunning)
                .buttonStyle(IconButtonStyle(tint: tint))
                .help(pomodoro.actionTitle)
                .accessibilityLabel(pomodoro.actionTitle)
                Button { pomodoro.skip() } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(IconButtonStyle())
                    .help(pomodoro.skipTitle)
                    .accessibilityLabel(pomodoro.skipTitle)
                Button { pomodoro.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(IconButtonStyle())
                    .help("Start over from the first round")
                    .accessibilityLabel("Start over")
            }
        }
    }
}

/// How far the phase has gone, redrawn every few seconds while it runs.
private struct PomodoroProgress: View {
    let pomodoro: PomodoroModel

    var body: some View {
        let timer = pomodoro.timer
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 5 : 3600)) { context in
            let length = max(timer.settings.length(of: timer.phase), 1)
            Bar(value: 1 - timer.remaining(at: context.date) / length, tint: timer.phase.tint, height: 5)
        }
    }
}

struct KeepAwakeCard: View {
    let keepAwake: KeepAwake

    var body: some View {
        Card("Keep Awake", symbol: "cup.and.saucer.fill", tint: Palette.cyan) {
            if keepAwake.isOn {
                Button("Turn Off") { keepAwake.stop() }
                    .buttonStyle(PillButtonStyle(isTinted: true, height: 22))
            }
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if keepAwake.isOn {
                        KeepAwakeRemaining(keepAwake: keepAwake)
                    } else {
                        Text("Off")
                    }
                }
                .font(.system(size: 32, weight: .semibold).monospacedDigit())
                .tracking(-0.5)
                .monospacedDigit()
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(KeepAwake.presets) { preset in
                    let isCurrent = keepAwake.isOn && keepAwake.presetID == preset.id
                    Button(preset.label) { keepAwake.start(preset) }
                        .buttonStyle(PillButtonStyle(isTinted: isCurrent, fillsWidth: true))
                }
            }
        }
    }

    private var detail: String {
        guard keepAwake.isOn else { return "the Mac sleeps as usual" }
        let what = keepAwake.keepsDisplayOn ? "display stays on" : "Mac stays awake"
        guard let until = keepAwake.until else { return "\(what) until turned off" }
        return "left · \(what) until \(until.formatted(date: .omitted, time: .shortened))"
    }
}

struct UsageCard: View {
    let usage: UsageModel

    var body: some View {
        Card("AI Usage", symbol: "gauge.with.dots.needle.33percent", tint: Palette.purple) {
            if let lastRead = usage.lastRead {
                Text("read \(lastRead.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
        } content: {
            if usage.readings.isEmpty {
                Text("No limits yet. Connect Claude Code or run Codex: right-click the island and open Settings → AI Usage.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            } else {
                let now = Date()
                VStack(spacing: 7) {
                    ForEach(usage.readings, id: \.provider) { reading in
                        ForEach(reading.windows, id: \.label) { window in
                            row(reading.provider, window, at: now)
                        }
                    }
                }
            }
        }
    }

    private func row(_ provider: String, _ window: UsageWindow, at now: Date) -> some View {
        let used = window.used(at: now)
        let isHigh = usage.highlightsHighUse && used >= 0.8
        // Plain strings, not localized keys: a "%" in a key would be read as a format specifier.
        let name: String = provider == "Claude" ? "Claude Code" : provider
        let percent: String = "\(Int((used * 100).rounded()))%"
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).font(.system(size: 12, weight: .semibold))
                Text("· " + Self.windowName(window.label))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                Text(percent)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(isHigh ? Palette.orange : .white)
                if usage.showsResetTimes, let reset = resetText(window, at: now) {
                    Text("· resets " + reset)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            Bar(value: used, tint: isHigh ? Palette.orange : Palette.purple, height: 3)
        }
    }

    /// "5h" as "5 hours", "7d" as "7 days".
    static func windowName(_ label: String) -> String {
        guard let unit = label.last, let number = Int(label.dropLast()) else { return label }
        switch unit {
        case "h": return number == 1 ? "1 hour" : "\(number) hours"
        case "d": return number == 7 ? "weekly" : "\(number) days"
        default: return label
        }
    }

    /// When the window starts over: the time if that is within a day, the weekday otherwise.
    private func resetText(_ window: UsageWindow, at now: Date) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        return resetsAt.timeIntervalSince(now) < 24 * 60 * 60
            ? resetsAt.formatted(date: .omitted, time: .shortened)
            : resetsAt.formatted(.dateTime.weekday(.abbreviated))
    }
}

struct CalendarCard: View {
    let calendar: CalendarModel

    var body: some View {
        Card("Calendar", symbol: "calendar", tint: Palette.red) {
            if calendar.access == .granted, !calendar.events.isEmpty {
                Text("Next \(min(calendar.events.count, 3))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
        } content: {
            CalendarAccessGate(calendar: calendar, empty: "Nothing else today or tomorrow.") {
                VStack(spacing: 8) {
                    ForEach(Array(calendar.events.prefix(3))) { event in
                        EventRow(event: event, isNext: event.id == calendar.events.first?.id, showsTime: false)
                    }
                }
            }
        }
    }
}

/// The calendar alone on a screen: today's date large, and the rest of today beside it.
struct CalendarWideCard: View {
    let calendar: CalendarModel

    var body: some View {
        let now = Date()
        HStack(spacing: IslandLayout.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Text(now, format: .dateTime.day())
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                Text(now, format: .dateTime.weekday(.wide))
                    .font(.system(size: 15, weight: .bold))
                Text(now, format: .dateTime.month(.wide).year())
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                if calendar.access == .granted {
                    Text(calendar.today.isEmpty ? "Nothing else today" : "\(calendar.today.count) more today")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(width: 150, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Card("Calendar", symbol: "calendar", tint: Palette.red) {
                Text("Rest of today")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            } content: {
                CalendarAccessGate(calendar: calendar, empty: "Nothing else today.") {
                    let today = calendar.today
                    if today.isEmpty {
                        Text("Nothing else today.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(today) { event in
                                EventRow(event: event, isNext: event.id == today.first?.id, showsTime: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Asks for access, explains a refusal, or shows the events.
private struct CalendarAccessGate<Content: View>: View {
    let calendar: CalendarModel
    let empty: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch calendar.access {
        case .notAsked:
            Button("Show My Events") {
                Task { await calendar.requestAccess() }
            }
            .buttonStyle(PillButtonStyle(isPrimary: true))
            .fixedSize()
        case .denied:
            note("Allow Brow under System Settings → Privacy & Security → Calendars.")
        case .granted where calendar.events.isEmpty:
            note(empty)
        case .granted:
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondary)
    }
}

/// Opens a call's link in whatever handles it. It is small to sit in an event row, or the island's usual white
/// pill when it has the room, as in a peek.
struct JoinButton: View {
    let url: URL
    var isProminent = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: { Text("Join") }
            .buttonStyle(JoinButtonStyle(isProminent: isProminent))
            .help("Join the call")
            .accessibilityLabel("Join the call")
    }
}

private struct JoinButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            PillButtonStyle(isPrimary: true).makeBody(configuration: configuration)
        } else {
            configuration.label
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 19)
                .background(Palette.blue.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
                .contentShape(Capsule())
                .modifier(PressFeedback(isPressed: configuration.isPressed, litByHover: false))
        }
    }
}

/// One event: its calendar's color, its title and time, and how soon it starts if it is next.
private struct EventRow: View {
    let event: CalendarModel.Event
    let isNext: Bool
    /// Whether a column of start times leads the row, as on the wide card.
    let showsTime: Bool

    var body: some View {
        let now = Date()
        HStack(spacing: 10) {
            if showsTime {
                Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            Capsule().fill(event.color).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .semibold))
                Text(subtitle(at: now))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if isNext, !event.isAllDay, event.start.timeIntervalSince(now) < 60 * 60 {
                EventCountdown(event: event)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .frame(height: 19)
                    .background(Palette.blue.opacity(0.22), in: Capsule())
            } else if !showsTime {
                Text(when(at: now))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
            if let url = event.meetingURL, !event.isAllDay,
               MeetingLink.isJoinable(start: event.start, end: event.end, at: now) {
                JoinButton(url: url)
            }
        }
        .monospacedDigit()
    }

    private func subtitle(at now: Date) -> String {
        if event.isAllDay { return "All day · \(event.calendarTitle)" }
        let range = "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
        return "\(range) · \(event.calendarTitle)"
    }

    /// Its time today, and the weekday with it from tomorrow on.
    private func when(at now: Date) -> String {
        if event.start <= now { return "Now" }
        return Calendar.current.isDate(event.start, inSameDayAs: now)
            ? event.start.formatted(date: .omitted, time: .shortened)
            : event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
