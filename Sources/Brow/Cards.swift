import BrowCore
import SwiftUI

/// The frame every feature's card shares: a glyph and an uppercase title, something on the right of it, and the
/// card's content below.
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
                Text(title.uppercased())
                    .font(Typeface.text(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                accessory
            }
            .frame(height: 20)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// A capsule button: white for the main action, a faint fill otherwise. Its fill is its hit area.
struct PillButtonStyle: ButtonStyle {
    var isPrimary = false
    var isSelected = false
    /// Whether it stretches to share a row equally with its neighbours.
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = isPrimary ? .white : isSelected ? Palette.paleBlue : Palette.track
        let text: Color = isPrimary ? .black : isSelected ? Palette.navy : .white
        configuration.label
            .font(Typeface.text(12, weight: isSelected ? .bold : .semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, fillsWidth ? 4 : 13)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 30)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A round button holding one glyph.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Palette.track.opacity(configuration.isPressed ? 0.6 : 1), in: Circle())
            .contentShape(Circle())
    }
}

/// A small tinted label, like "Focus · 2 of 4".
private struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Typeface.number(10, weight: .semibold))
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
                    .font(Typeface.number(34, weight: .bold))
                    .monospacedDigit()
                Text("of \(Pomodoro.clockText(timer.settings.length(of: timer.phase)))")
                    .font(Typeface.text(11))
                    .foregroundStyle(Palette.secondary)
            }
            PomodoroProgress(pomodoro: pomodoro)
            HStack(spacing: 6) {
                Button { pomodoro.toggle() } label: {
                    Label(pomodoro.actionTitle, systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
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
        Card("Keep Awake", symbol: "cup.and.saucer.fill", tint: Palette.paleBlue) {
            if keepAwake.isOn {
                Button("Turn off") { keepAwake.stop() }
                    .buttonStyle(.plain)
                    .font(Typeface.text(12, weight: .semibold))
                    .foregroundStyle(Palette.paleBlue)
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
                .font(Typeface.number(34, weight: .bold))
                .monospacedDigit()
                Text(detail)
                    .font(Typeface.text(11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(KeepAwake.presets) { preset in
                    let isCurrent = keepAwake.isOn && keepAwake.presetID == preset.id
                    Button(preset.label) { keepAwake.start(preset) }
                        .buttonStyle(PillButtonStyle(isSelected: isCurrent, fillsWidth: true))
                        .overlay {
                            // The default length is outlined while off, as the one to pick without thinking.
                            if !keepAwake.isOn && preset.id == keepAwake.defaultPresetID {
                                Capsule().stroke(Palette.paleBlue.opacity(0.7), lineWidth: 1.5)
                            }
                        }
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
        Card("AI Usage", symbol: "gauge.with.dots.needle.33percent", tint: .white) {
            if let lastRead = usage.lastRead {
                Text("read \(lastRead.formatted(date: .omitted, time: .shortened))")
                    .font(Typeface.text(10))
                    .foregroundStyle(Palette.secondary)
            }
        } content: {
            if usage.readings.isEmpty {
                Text("No limits yet. Connect Claude Code or run Codex: right-click the island and open Settings → AI Usage.")
                    .font(Typeface.text(11))
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
                Text(name).font(Typeface.text(12, weight: .semibold))
                Text("· " + Self.windowName(window.label))
                    .font(Typeface.text(12))
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                Text(percent)
                    .font(Typeface.number(12, weight: .bold))
                    .foregroundStyle(isHigh ? Palette.amber : .white)
                if usage.showsResetTimes, let reset = resetText(window, at: now) {
                    Text("· resets " + reset)
                        .font(Typeface.text(10))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            Bar(value: used, tint: isHigh ? Palette.amber : Palette.paleBlue, height: 3)
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
        Card("Calendar", symbol: "calendar", tint: Palette.teal) {
            if calendar.access == .granted, !calendar.events.isEmpty {
                Text("Next \(min(calendar.events.count, 3))")
                    .font(Typeface.text(10))
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
                Text("TODAY")
                    .font(Typeface.text(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.secondary)
                Text(now, format: .dateTime.day())
                    .font(Typeface.number(56, weight: .bold))
                Text(now, format: .dateTime.weekday(.wide))
                    .font(Typeface.text(15, weight: .bold))
                Text(now, format: .dateTime.month(.wide).year())
                    .font(Typeface.text(11))
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                if calendar.access == .granted {
                    Text(calendar.today.isEmpty ? "Nothing else today" : "\(calendar.today.count) more today")
                        .font(Typeface.text(10))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(width: 150, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))

            Card("Calendar", symbol: "calendar", tint: Palette.teal) {
                Text("Rest of today")
                    .font(Typeface.text(10))
                    .foregroundStyle(Palette.secondary)
            } content: {
                CalendarAccessGate(calendar: calendar, empty: "Nothing else today.") {
                    let today = calendar.today
                    if today.isEmpty {
                        Text("Nothing else today.")
                            .font(Typeface.text(11))
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
            .font(Typeface.text(11))
            .foregroundStyle(Palette.secondary)
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
                    .font(Typeface.number(11, weight: .bold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            Capsule().fill(event.color).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(Typeface.text(12, weight: .semibold))
                Text(subtitle(at: now))
                    .font(Typeface.text(10))
                    .foregroundStyle(Palette.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if isNext, !event.isAllDay, event.start.timeIntervalSince(now) < 60 * 60 {
                EventCountdown(event: event)
                    .font(Typeface.number(11, weight: .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 19)
                    .background(Palette.teal.opacity(0.16), in: Capsule())
            } else if !showsTime {
                Text(when(at: now))
                    .font(Typeface.text(11))
                    .foregroundStyle(Palette.secondary)
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
