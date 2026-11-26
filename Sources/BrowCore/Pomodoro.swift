import Foundation

/// A pomodoro cycle as a plain value: focus, a short break, and a long break after every few focus rounds.
///
/// It never reads the clock. Callers pass `now`, and a running phase is stored as the date it ends, so the
/// countdown stays right across sleep and needs no ticking timer to stay in step.
public struct Pomodoro: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case focus, shortBreak, longBreak
    }

    public struct Settings: Equatable, Sendable {
        public var focus: TimeInterval
        public var shortBreak: TimeInterval
        public var longBreak: TimeInterval
        /// A long break follows every this many finished focus rounds.
        public var roundsUntilLongBreak: Int

        public init(focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60,
                    longBreak: TimeInterval = 15 * 60, roundsUntilLongBreak: Int = 4) {
            self.focus = focus
            self.shortBreak = shortBreak
            self.longBreak = longBreak
            self.roundsUntilLongBreak = roundsUntilLongBreak
        }

        public func length(of phase: Phase) -> TimeInterval {
            switch phase {
            case .focus: focus
            case .shortBreak: shortBreak
            case .longBreak: longBreak
            }
        }
    }

    public enum Run: Equatable, Sendable {
        /// Waiting to be started, showing the phase's full length.
        case ready
        case running(until: Date)
        case paused(remaining: TimeInterval)
    }

    public var settings: Settings
    public private(set) var phase = Phase.focus
    public private(set) var run = Run.ready
    /// Focus rounds that ran to their end. Skipped ones don't count.
    public private(set) var completedFocusRounds = 0

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// False only while it waits at the start of a phase: then there is nothing worth showing beside the notch.
    public var isActive: Bool { run != .ready }

    public var isRunning: Bool { endDate != nil }

    /// When the running phase ends; nil unless running.
    public var endDate: Date? {
        if case .running(let end) = run { end } else { nil }
    }

    /// The round shown to the owner, from 1 to `roundsUntilLongBreak`. A break belongs to the round before it.
    public var currentRound: Int {
        let rounds = max(settings.roundsUntilLongBreak, 1)
        let finished = phase == .focus ? completedFocusRounds : completedFocusRounds - 1
        return max(finished, 0) % rounds + 1
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch run {
        case .ready: settings.length(of: phase)
        case .running(let end): max(end.timeIntervalSince(now), 0)
        case .paused(let remaining): remaining
        }
    }

    /// Starts the phase, or carries on after a pause.
    public mutating func start(at now: Date) {
        switch run {
        case .ready: run = .running(until: now.addingTimeInterval(settings.length(of: phase)))
        case .paused(let remaining): run = .running(until: now.addingTimeInterval(remaining))
        case .running: break
        }
    }

    public mutating func pause(at now: Date) {
        guard case .running(let end) = run else { return }
        run = .paused(remaining: max(end.timeIntervalSince(now), 0))
    }

    /// Moves on to the next phase without counting an unfinished focus round.
    public mutating func skip() {
        advance(countingFocus: false)
        run = .ready
    }

    /// Back to the first focus round.
    public mutating func reset() {
        phase = .focus
        completedFocusRounds = 0
        run = .ready
    }

    /// Ends the running phase if its time has come, and moves on to the next one.
    /// - Returns: The phase that just finished, or nil if nothing was due.
    public mutating func finishIfDue(at now: Date, autoStartNext: Bool) -> Phase? {
        guard case .running(let end) = run, now >= end else { return nil }
        let finished = phase
        advance(countingFocus: true)
        run = .ready
        if autoStartNext { start(at: now) }
        return finished
    }

    private mutating func advance(countingFocus: Bool) {
        switch phase {
        case .focus:
            if countingFocus { completedFocusRounds += 1 }
            let earnedLongBreak = countingFocus && completedFocusRounds % max(settings.roundsUntilLongBreak, 1) == 0
            phase = earnedLongBreak ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
    }

    /// Seconds as a countdown, like "24:59" or "0:07". Rounded up, so it reads 0:00 only once time is up.
    public static func clockText(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
