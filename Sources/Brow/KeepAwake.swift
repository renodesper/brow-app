import Foundation
import IOKit.ps
import Observation

/// Keeps the Mac awake, and the display on unless the owner chose otherwise, like `caffeinate -d`.
///
/// It holds one power assertion and does nothing else while on: macOS itself keeps the Mac awake for as long as
/// the assertion lives, and drops it if the app quits or crashes. With the battery cut-off on, it also listens
/// for macOS's own note that the battery changed; nothing polls.
@MainActor
@Observable
final class KeepAwake {
    /// One of the lengths it can be turned on for.
    struct Preset: Identifiable {
        let id: String
        /// Short, for the island's buttons.
        let label: String
        /// For menus and settings.
        let title: String
        /// nil is until it is turned off.
        let duration: TimeInterval?
    }

    static let presets = [
        Preset(id: "30m", label: "30m", title: "For 30 Minutes", duration: 30 * 60),
        Preset(id: "1h", label: "1h", title: "For 1 Hour", duration: 60 * 60),
        Preset(id: "2h", label: "2h", title: "For 2 Hours", duration: 2 * 60 * 60),
        Preset(id: "none", label: "No end", title: "Until Turned Off", duration: nil),
    ]

    static let batteryLevels = [10, 20, 30]

    private(set) var isOn = false
    /// When it turns itself off; nil while off or on without an end.
    private(set) var until: Date?
    /// The preset it was turned on with.
    private(set) var presetID: String?

    /// The preset the island suggests first.
    var defaultPresetID: String {
        didSet { defaults.set(defaultPresetID, forKey: Key.defaultPreset) }
    }

    /// Whether the display stays on too, or only the Mac.
    var keepsDisplayOn: Bool {
        didSet {
            defaults.set(keepsDisplayOn, forKey: Key.keepsDisplayOn)
            if isOn { holdAssertion() }
        }
    }

    var batteryCutoffEnabled: Bool {
        didSet {
            defaults.set(batteryCutoffEnabled, forKey: Key.batteryCutoffEnabled)
            watchBattery()
        }
    }

    /// The battery percentage below which it turns itself off.
    var batteryCutoffLevel: Int {
        didSet {
            defaults.set(batteryCutoffLevel, forKey: Key.batteryCutoffLevel)
            checkBattery()
        }
    }

    var showsBesideNotch: Bool {
        didSet { defaults.set(showsBesideNotch, forKey: Key.showsBesideNotch) }
    }

    var defaultPreset: Preset {
        Self.presets.first { $0.id == defaultPresetID } ?? Self.presets[1]
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var assertion: NSObjectProtocol?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var batterySource: CFRunLoopSource?
    @ObservationIgnored private var batteryObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultPresetID = defaults.string(forKey: Key.defaultPreset) ?? "1h"
        keepsDisplayOn = defaults.bool(Key.keepsDisplayOn, default: true)
        batteryCutoffEnabled = defaults.bool(Key.batteryCutoffEnabled, default: true)
        batteryCutoffLevel = defaults.int(Key.batteryCutoffLevel, default: 20)
        showsBesideNotch = defaults.bool(Key.showsBesideNotch, default: true)
        batteryObserver = NotificationCenter.default.addObserver(forName: .powerSourceChanged, object: nil,
                                                                 queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkBattery() }
        }
        resumeIfTimed()
    }

    func start(_ preset: Preset) {
        start(for: preset.duration)
        presetID = preset.id
        if until != nil { defaults.set(preset.id, forKey: Key.resumePreset) }
    }

    func start(for duration: TimeInterval?) {
        stop()
        holdAssertion()
        isOn = true
        watchBattery()
        checkBattery()
        guard isOn, let duration else { return }
        until = Date().addingTimeInterval(duration)
        // Remembered, so a relaunch before it ends can pick it up again. One that never ends is not.
        defaults.set(until, forKey: Key.resumeUntil)
        // One sleeping task for the whole duration. Its clock keeps counting while the Mac sleeps (after the
        // lid was closed, say), so it ends on time rather than late.
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        if let assertion { ProcessInfo.processInfo.endActivity(assertion) }
        assertion = nil
        isOn = false
        until = nil
        presetID = nil
        defaults.removeObject(forKey: Key.resumeUntil)
        defaults.removeObject(forKey: Key.resumePreset)
        watchBattery()
    }

    /// Turns itself back on, for what is left of it, if the app was closed during a timed run.
    private func resumeIfTimed() {
        guard let end = defaults.object(forKey: Key.resumeUntil) as? Date, end.timeIntervalSinceNow > 0 else {
            defaults.removeObject(forKey: Key.resumeUntil)
            defaults.removeObject(forKey: Key.resumePreset)
            return
        }
        let saved = defaults.string(forKey: Key.resumePreset)
        start(for: end.timeIntervalSinceNow)
        if isOn { presetID = saved }
    }

    /// Takes the power assertion, replacing the one held, so a change of what stays awake applies at once.
    private func holdAssertion() {
        if let assertion { ProcessInfo.processInfo.endActivity(assertion) }
        let options: ProcessInfo.ActivityOptions = keepsDisplayOn
            ? [.idleDisplaySleepDisabled, .idleSystemSleepDisabled]
            : [.idleSystemSleepDisabled]
        assertion = ProcessInfo.processInfo.beginActivity(options: options, reason: "Keep Awake is on")
    }

    /// Listens for battery changes only while on with the cut-off enabled, and not at all otherwise.
    private func watchBattery() {
        let wanted = isOn && batteryCutoffEnabled
        if wanted, batterySource == nil {
            batterySource = PowerSource.makeChangeSource()
            if let batterySource { CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .defaultMode) }
        } else if !wanted, let source = batterySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            batterySource = nil
        }
    }

    private func checkBattery() {
        guard isOn, batteryCutoffEnabled, let battery = PowerSource.battery(),
              battery.isDischarging, battery.percent < batteryCutoffLevel else { return }
        stop()
    }

    private enum Key {
        static let defaultPreset = "keepAwake.defaultPreset"
        static let keepsDisplayOn = "keepAwake.keepsDisplayOn"
        static let batteryCutoffEnabled = "keepAwake.batteryCutoffEnabled"
        static let batteryCutoffLevel = "keepAwake.batteryCutoffLevel"
        static let showsBesideNotch = "keepAwake.showsBesideNotch"
        static let resumeUntil = "keepAwake.resumeUntil"
        static let resumePreset = "keepAwake.resumePreset"
    }
}

extension Notification.Name {
    /// Posted when macOS reports a change of power source or battery level.
    static let powerSourceChanged = Notification.Name("Brow.powerSourceChanged")
}

/// The battery, read through IOKit's power-source functions.
enum PowerSource {
    struct Battery {
        var percent: Int
        var isDischarging: Bool
    }

    /// The internal battery, or nil on a Mac without one.
    static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = description["Current Capacity"] as? Int,
                  let max = description["Max Capacity"] as? Int, max > 0 else { continue }
            let state = description["Power Source State"] as? String
            return Battery(percent: current * 100 / max, isDischarging: state == "Battery Power")
        }
        return nil
    }

    /// A run-loop source that posts `powerSourceChanged` whenever macOS reports a change.
    static func makeChangeSource() -> CFRunLoopSource? {
        IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .powerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue()
    }
}
