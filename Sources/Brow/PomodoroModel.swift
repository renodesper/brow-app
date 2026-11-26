import AppKit
import BrowCore
import Observation

/// Runs the pomodoro cycle against the clock and remembers its settings.
///
/// The cycle itself is `Pomodoro`, a plain value. This adds the two things a value can't do: wake up once when
/// the running phase ends, and save what the owner chose.
@MainActor
@Observable
final class PomodoroModel {
    static let sounds = ["None", "Glass", "Ping", "Tink", "Pop", "Hero"]

    private(set) var timer: Pomodoro

    var startsBreaksAutomatically: Bool {
        didSet { defaults.set(startsBreaksAutomatically, forKey: Key.autoBreaks) }
    }

    var startsFocusAutomatically: Bool {
        didSet { defaults.set(startsFocusAutomatically, forKey: Key.autoFocus) }
    }

    /// Whether the island opens a little when a phase ends.
    var peeksOnPhaseEnd: Bool {
        didSet { defaults.set(peeksOnPhaseEnd, forKey: Key.peeks) }
    }

    /// A system sound's name, or "None".
    var soundName: String {
        didSet { defaults.set(soundName, forKey: Key.sound) }
    }

    var showsBesideNotch: Bool {
        didSet { defaults.set(showsBesideNotch, forKey: Key.showsBesideNotch) }
    }

    var focusMinutes: Int {
        get { Int(timer.settings.focus / 60) }
        set { setLength(of: .focus, minutes: newValue) }
    }

    var shortBreakMinutes: Int {
        get { Int(timer.settings.shortBreak / 60) }
        set { setLength(of: .shortBreak, minutes: newValue) }
    }

    var longBreakMinutes: Int {
        get { Int(timer.settings.longBreak / 60) }
        set { setLength(of: .longBreak, minutes: newValue) }
    }

    /// A long break follows every this many finished focus rounds.
    var roundsUntilLongBreak: Int {
        get { timer.settings.roundsUntilLongBreak }
        set {
            timer.settings.roundsUntilLongBreak = max(newValue, 1)
            defaults.set(timer.settings.roundsUntilLongBreak, forKey: Key.rounds)
        }
    }

    /// Called as a phase runs out, with the phase that ended.
    @ObservationIgnored var onPhaseFinished: ((Pomodoro.Phase) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var endOfPhase: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var settings = Pomodoro.Settings()
        if let minutes = Self.savedMinutes(.focus, in: defaults) { settings.focus = minutes * 60 }
        if let minutes = Self.savedMinutes(.shortBreak, in: defaults) { settings.shortBreak = minutes * 60 }
        if let minutes = Self.savedMinutes(.longBreak, in: defaults) { settings.longBreak = minutes * 60 }
        let rounds = defaults.integer(forKey: Key.rounds)
        if rounds > 0 { settings.roundsUntilLongBreak = rounds }
        timer = Pomodoro(settings: settings)
        // Version 0.1 had one switch for both; it carries over to breaks.
        let oldAutoStart = defaults.object(forKey: Key.oldAutoStart) as? Bool
        startsBreaksAutomatically = defaults.bool(Key.autoBreaks, default: oldAutoStart ?? true)
        startsFocusAutomatically = defaults.bool(Key.autoFocus, default: false)
        peeksOnPhaseEnd = defaults.bool(Key.peeks, default: true)
        soundName = defaults.string(forKey: Key.sound) ?? "Glass"
        showsBesideNotch = defaults.bool(Key.showsBesideNotch, default: true)
        // A phase that ran out while the Mac slept is noticed as it wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finishPhaseIfDue() }
        }
    }

    /// What the one start button means right now.
    var actionTitle: String {
        if timer.isRunning { return "Pause" }
        return timer.isActive ? "Resume" : "Start"
    }

    /// The next phase's name, for "Skip to Break" and the like.
    var skipTitle: String {
        timer.phase == .focus ? "Skip to Break" : "Skip to Focus"
    }

    /// Starts, pauses or carries on, whichever the one button means right now.
    func toggle() {
        if timer.isRunning {
            timer.pause(at: Date())
        } else {
            timer.start(at: Date())
        }
        armEndOfPhase()
    }

    func skip() {
        timer.skip()
        armEndOfPhase()
    }

    func reset() {
        timer.reset()
        armEndOfPhase()
    }

    /// Takes effect from the next time the phase starts; a phase already running keeps its end.
    func setLength(of phase: Pomodoro.Phase, minutes: Int) {
        let minutes = min(max(minutes, 1), 180)
        let seconds = TimeInterval(minutes * 60)
        switch phase {
        case .focus: timer.settings.focus = seconds
        case .shortBreak: timer.settings.shortBreak = seconds
        case .longBreak: timer.settings.longBreak = seconds
        }
        defaults.set(minutes, forKey: Key.minutes(phase))
    }

    private func finishPhaseIfDue() {
        let now = Date()
        if let finished = timer.finishIfDue(at: now, autoStartNext: false) {
            // The phase now waiting is the next one: a break after focus, focus after a break.
            let startsByItself = timer.phase == .focus ? startsFocusAutomatically : startsBreaksAutomatically
            if startsByItself { timer.start(at: now) }
            onPhaseFinished?(finished)
        }
        armEndOfPhase()
    }

    /// One sleeping task until the running phase ends, and none while nothing runs. The display's ticking is
    /// the view's own business and stops when the view goes away.
    private func armEndOfPhase() {
        endOfPhase?.cancel()
        endOfPhase = nil
        guard let end = timer.endDate else { return }
        let wait = max(end.timeIntervalSinceNow, 0)
        endOfPhase = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.finishPhaseIfDue()
        }
    }

    private static func savedMinutes(_ phase: Pomodoro.Phase, in defaults: UserDefaults) -> TimeInterval? {
        let minutes = defaults.integer(forKey: Key.minutes(phase))
        return minutes > 0 ? TimeInterval(minutes) : nil
    }

    private enum Key {
        static let oldAutoStart = "pomodoro.autoStart"
        static let autoBreaks = "pomodoro.startsBreaksAutomatically"
        static let autoFocus = "pomodoro.startsFocusAutomatically"
        static let peeks = "pomodoro.peeksOnPhaseEnd"
        static let sound = "pomodoro.sound"
        static let showsBesideNotch = "pomodoro.showsBesideNotch"
        static let rounds = "pomodoro.roundsUntilLongBreak"
        static func minutes(_ phase: Pomodoro.Phase) -> String { "pomodoro.minutes.\(phase.rawValue)" }
    }
}
