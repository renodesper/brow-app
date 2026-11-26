import Foundation

/// Anything with a start and an end, like a calendar event.
public protocol Scheduled {
    var start: Date { get }
    var end: Date { get }
}

/// Decides which event deserves a place beside the notch, and when that next changes.
///
/// Like `Pomodoro`, it never reads the clock: callers pass `now`. Knowing the next moment of change lets the
/// app sleep until then instead of checking the time over and over.
public enum Agenda {
    /// How long before its start an event shows beside the notch, unless the owner chose otherwise.
    public static let lead: TimeInterval = 15 * 60
    /// The lead times the owner can choose from.
    public static let leadChoices: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60, 30 * 60]
    /// How long it stays there after it started, as "Now".
    public static let linger: TimeInterval = 5 * 60

    /// The event to show beside the notch at `now`, if any.
    public static func near<Event: Scheduled>(_ events: [Event], at now: Date, lead: TimeInterval = Agenda.lead) -> Event? {
        let showing = events.filter { shownRange(of: $0, lead: lead).contains(now) }
        // One about to start matters more than one already under way.
        return showing.filter { $0.start > now }.min { $0.start < $1.start }
            ?? showing.max { $0.start < $1.start }
    }

    /// The next moment after `now` at which `near` gives a different answer or its event starts.
    public static func nextChange<Event: Scheduled>(_ events: [Event], after now: Date,
                                                    lead: TimeInterval = Agenda.lead) -> Date? {
        events.flatMap { event -> [Date] in
            let shown = shownRange(of: event, lead: lead)
            return [shown.lowerBound, event.start, shown.upperBound]
        }
        .filter { $0 > now }
        .min()
    }

    /// The time until `start`, short enough for beside the notch: "in 12m", then "Now". Minutes round up, so
    /// it says "Now" only once the event has started.
    public static func countdownText(to start: Date, at now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes > 0 ? "in \(minutes)m" : "Now"
    }

    /// From `lead` before the start until `linger` after it, or until the event's end if that comes first.
    private static func shownRange<Event: Scheduled>(of event: Event, lead: TimeInterval) -> Range<Date> {
        let from = event.start.addingTimeInterval(-lead)
        let until = max(min(event.start.addingTimeInterval(linger), event.end), event.start)
        return from..<until
    }
}
