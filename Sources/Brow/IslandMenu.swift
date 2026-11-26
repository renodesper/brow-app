import AppKit
import BrowCore

/// The menu that opens on a right-click on the island: Keep Awake and Pomodoro, then Settings and Quit.
///
/// The app has no Dock icon and no menu bar icon, so this is where Settings and Quit live. Everything else is in
/// the Settings window.
@MainActor
final class IslandMenu: NSObject {
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    /// Built as it opens, so its checkmarks and titles always match what is going on.
    func make() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(keepAwakeItem())
        menu.addItem(pomodoroItem())
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        let quit = NSMenuItem(title: "Quit Brow", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func keepAwakeItem() -> NSMenuItem {
        let keepAwake = model.keepAwake
        let parent = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if let until = keepAwake.until {
            submenu.addItem(status("On until \(until.formatted(date: .omitted, time: .shortened))"))
            submenu.addItem(.separator())
        }
        submenu.addItem(item("Off", #selector(turnKeepAwakeOff), checked: !keepAwake.isOn))
        submenu.addItem(.separator())
        for (index, preset) in KeepAwake.choices.enumerated() {
            let option = item(preset.title, #selector(startKeepAwake(_:)),
                              checked: keepAwake.isOn && keepAwake.presetID == preset.id)
            option.tag = index
            submenu.addItem(option)
        }
        parent.submenu = submenu
        return parent
    }

    private func pomodoroItem() -> NSMenuItem {
        let pomodoro = model.pomodoro
        let timer = pomodoro.timer
        let parent = NSMenuItem(title: "Pomodoro", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let left = Pomodoro.clockText(timer.remaining(at: Date()))
        let state: String
        if timer.isRunning {
            state = "\(timer.phase.title) · \(left) left"
        } else if timer.isActive {
            state = "\(timer.phase.title) · paused at \(left)"
        } else {
            state = "Not running · next: \(timer.phase.title)"
        }
        submenu.addItem(status(state))
        submenu.addItem(.separator())
        submenu.addItem(item(pomodoro.actionTitle, #selector(togglePomodoro)))
        submenu.addItem(item(pomodoro.skipTitle, #selector(skipPomodoro)))
        let reset = item("Start Over", #selector(resetPomodoro))
        reset.isEnabled = timer.isActive || timer.completedFocusRounds > 0 || timer.phase != .focus
        submenu.addItem(reset)
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func status(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func turnKeepAwakeOff() {
        model.keepAwake.stop()
    }

    @objc private func startKeepAwake(_ sender: NSMenuItem) {
        let presets = KeepAwake.choices
        guard presets.indices.contains(sender.tag) else { return }
        model.keepAwake.start(presets[sender.tag])
    }

    @objc private func togglePomodoro() {
        model.pomodoro.toggle()
    }

    @objc private func skipPomodoro() {
        model.pomodoro.skip()
    }

    @objc private func resetPomodoro() {
        model.pomodoro.reset()
    }

    @objc private func showSettings() {
        openSettings()
    }
}
