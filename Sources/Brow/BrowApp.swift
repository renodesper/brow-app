import AppKit
import BrowCore
import Carbon.HIToolbox

/// AppKit owns the app's lifecycle. There is no storyboard and no SwiftUI `App`, which would bring a scene and
/// a main menu this app never shows.
@main
@MainActor
enum BrowApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var displays: IslandDisplays!
    private var menu: IslandMenu!
    private var settings: SettingsWindowController!
    private var settingsShortcut: GlobalShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        settings = SettingsWindowController(model: model)
        // No Dock icon and no menu bar icon: a right-click on the island is the way to Settings and Quit.
        menu = IslandMenu(model: model, openSettings: { [weak self] in self?.settings.show() })
        displays = IslandDisplays(app: model, makeMenu: { [weak self] in self?.menu.make() ?? NSMenu() })

        // With no Dock icon and no menu bar icon, the island can be out of reach (hidden behind a full-screen app,
        // say). This shortcut always gets to Settings. It is left out of the Settings text if another app has it.
        settingsShortcut = GlobalShortcut(keyCode: kVK_ANSI_Comma, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.settings.show()
        }
        if settingsShortcut != nil { model.settingsShortcut = "⌃⌥⌘," }

        // No Dock icon and no menu bar icon, so launching shows nothing: a short hello says the app is running. It
        // waits a moment so the island has settled in its place first.
        if model.preferences.showsLaunchHello {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.displays.showPeek(.hello, for: .seconds(2.5))
            }
        }

        model.pomodoro.onPhaseFinished = { [weak self] phase in
            guard let self else { return }
            let pomodoro = self.model.pomodoro
            if pomodoro.soundName != "None" { NSSound(named: pomodoro.soundName)?.play() }
            if pomodoro.peeksOnPhaseEnd { self.displays.showPeek(.phaseFinished(phase)) }
        }
        // An event starting opens the island for a moment, without a sound.
        model.calendar.onEventStarted = { [weak self] event in
            guard let self, self.model.calendar.peeksOnStart else { return }
            self.displays.showPeek(.eventStarted(event))
        }
    }

    /// Opening the app again, from Finder or Spotlight, shows the settings: there is nothing else to show.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}
