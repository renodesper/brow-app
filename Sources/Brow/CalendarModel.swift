import AppKit
import EventKit
import BrowCore
import Observation
import SwiftUI

/// Events from the calendars macOS already knows (iCloud, Google, Exchange and so on), read through EventKit.
///
/// The open island lists the next few. Beside the notch, one event shows as a live activity from a little before
/// it starts. Nothing polls for that: events are read when something could have changed (the island opens, a
/// calendar changes, the day changes, the Mac wakes), and one sleeping task waits for the next moment an event
/// should appear, start or leave (`Agenda.nextChange`).
@MainActor
@Observable
final class CalendarModel {
    struct Event: Identifiable, Equatable, Scheduled {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: Color
        let calendarTitle: String
        let isAllDay: Bool
        /// The link that joins the call, if the event's URL, location or notes hold one.
        let meetingURL: URL?
    }

    /// A calendar the owner can include or leave out.
    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let color: Color
        let accountID: String
        let accountTitle: String
        let accountKind: AccountKind
    }

    /// The kind of account a calendar lives in, for its icon and label. In the order they are listed.
    enum AccountKind: Int, Comparable {
        case iCloud, calDAV, exchange, local, subscribed, birthdays

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        init(_ source: EKSource) {
            switch source.sourceType {
            case .mobileMe: self = .iCloud
            case .calDAV: self = source.title.localizedCaseInsensitiveContains("icloud") ? .iCloud : .calDAV
            case .exchange: self = .exchange
            case .local: self = .local
            case .subscribed: self = .subscribed
            case .birthdays: self = .birthdays
            @unknown default: self = .calDAV
            }
        }

        var label: String {
            switch self {
            case .iCloud: "iCloud"
            case .calDAV: "Calendar account"
            case .exchange: "Exchange"
            case .local: "On this Mac"
            case .subscribed: "Subscribed"
            case .birthdays: "Birthdays"
            }
        }

        var symbol: String {
            switch self {
            case .iCloud: "icloud"
            case .calDAV: "person.crop.circle"
            case .exchange: "envelope"
            case .local: "laptopcomputer"
            case .subscribed: "dot.radiowaves.up.forward"
            case .birthdays: "gift"
            }
        }

        /// Whether the list starts folded: these hold little the owner picks by hand.
        var startsFolded: Bool { self == .subscribed || self == .birthdays }
    }

    /// An account and its calendars, for the settings.
    struct Account: Identifiable {
        let id: String
        let title: String
        let kind: AccountKind
        let calendars: [CalendarInfo]
    }

    enum Access {
        case notAsked, granted, denied
    }

    static let maxEvents = 4

    private(set) var access: Access
    /// The next few events, for the open island.
    private(set) var events: [Event] = []
    /// The event that shows beside the notch right now, if any.
    private(set) var near: Event?
    /// Every calendar on this Mac, for the settings. Read when the settings ask for it.
    private(set) var calendars: [CalendarInfo] = []

    /// Whether events show beside the notch at all.
    var announcesEvents: Bool {
        didSet {
            defaults.set(announcesEvents, forKey: Key.announces)
            refresh()
            updateNear()
        }
    }

    /// How many minutes before its start an event shows beside the notch.
    var leadMinutes: Int {
        didSet {
            defaults.set(leadMinutes, forKey: Key.lead)
            updateNear()
        }
    }

    /// Whether the island opens for a moment as an event starts.
    var peeksOnStart: Bool {
        didSet { defaults.set(peeksOnStart, forKey: Key.peeks) }
    }

    var includesAllDay: Bool {
        didSet {
            defaults.set(includesAllDay, forKey: Key.allDay)
            refresh()
        }
    }

    /// Calendars the owner left out, by identifier. Ones added later are included until left out.
    var excludedCalendarIDs: Set<String> {
        didSet {
            defaults.set(Array(excludedCalendarIDs), forKey: Key.excluded)
            refresh()
        }
    }

    /// Called once as an event starts.
    @ObservationIgnored var onEventStarted: ((Event) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    /// Made on first use: an event store costs a few megabytes, and someone who never allows access never
    /// pays for one.
    @ObservationIgnored private lazy var store = EKEventStore()
    /// Every event from now until the end of tomorrow.
    @ObservationIgnored private var upcoming: [Event] = []
    @ObservationIgnored private var announcedID: String?
    @ObservationIgnored private var nextChange: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        announcesEvents = defaults.bool(Key.announces, default: true)
        leadMinutes = defaults.int(Key.lead, default: Int(Agenda.lead / 60))
        peeksOnStart = defaults.bool(Key.peeks, default: true)
        includesAllDay = defaults.bool(Key.allDay, default: false)
        excludedCalendarIDs = Set(defaults.stringArray(forKey: Key.excluded) ?? [])
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notAsked
        default: access = .denied
        }

        let refreshLater: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main,
                                                   using: refreshLater),
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main,
                                                   using: refreshLater),
            // A sleeping task can't be trusted across the Mac's own sleep, so waking starts over.
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                  using: refreshLater),
        ]
        if announcesEvents { refresh() }
    }

    /// The events left today, for the calendar's wide card.
    var today: [Event] {
        let now = Date()
        return events.filter { Calendar.current.isDate($0.start, inSameDayAs: now) || $0.start <= now }
    }

    /// Shows macOS's own permission prompt, once.
    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        refresh()
        loadCalendars()
    }

    /// Reads the list of calendars, for the settings.
    func loadCalendars() {
        guard access == .granted else { return }
        calendars = store.calendars(for: .event)
            .map {
                CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color),
                             accountID: $0.source.sourceIdentifier, accountTitle: $0.source.title,
                             accountKind: AccountKind($0.source))
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The calendars grouped by the account they belong to: iCloud first, then other accounts, this Mac, and the
    /// subscribed and birthday calendars last.
    var accounts: [Account] {
        Dictionary(grouping: calendars, by: \.accountID)
            .compactMap { id, calendars -> Account? in
                guard let first = calendars.first else { return nil }
                return Account(id: id, title: first.accountTitle, kind: first.accountKind, calendars: calendars)
            }
            .sorted { ($0.kind, $0.title) < ($1.kind, $1.title) }
    }

    /// Reads the events from now until the end of tomorrow, the one going on now included.
    func refresh() {
        guard access == .granted else { return }
        let now = Date()
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return }
        let included = store.calendars(for: .event).filter { !excludedCalendarIDs.contains($0.calendarIdentifier) }
        if included.isEmpty {
            upcoming = []
        } else {
            let predicate = store.predicateForEvents(withStart: now, end: end, calendars: included)
            upcoming = store.events(matching: predicate)
                .filter { (includesAllDay || !$0.isAllDay) && $0.status != .canceled }
                .sorted { $0.startDate < $1.startDate }
                .map { event in
                    // A repeating event has one identifier for all its days, so the start goes into the id too.
                    Event(id: "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)",
                          title: event.title ?? "Untitled", start: event.startDate, end: event.endDate,
                          color: Color(nsColor: event.calendar.color), calendarTitle: event.calendar.title,
                          isAllDay: event.isAllDay,
                          meetingURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
                }
        }
        events = Array(upcoming.prefix(Self.maxEvents))
        updateNear()
    }

    /// Works out which event shows beside the notch now, and sleeps until that next changes.
    private func updateNear() {
        nextChange?.cancel()
        nextChange = nil
        guard announcesEvents, access == .granted else {
            near = nil
            return
        }
        let now = Date()
        let lead = TimeInterval(leadMinutes * 60)
        // All-day events have no moment to count down to.
        let timed = upcoming.filter { !$0.isAllDay }
        let event = Agenda.near(timed, at: now, lead: lead)
        if near != event { near = event }
        if let event, event.start <= now, announcedID != event.id {
            announcedID = event.id
            onEventStarted?(event)
        }
        guard let change = Agenda.nextChange(timed, after: now, lead: lead) else { return }
        nextChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(change.timeIntervalSinceNow), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            // Read again rather than only recomputed, so an event that ended also leaves the open island.
            self?.refresh()
        }
    }

    private enum Key {
        static let announces = "calendar.announcesEvents"
        static let lead = "calendar.leadMinutes"
        static let peeks = "calendar.peeksOnStart"
        static let allDay = "calendar.includesAllDay"
        static let excluded = "calendar.excludedCalendars"
    }
}
