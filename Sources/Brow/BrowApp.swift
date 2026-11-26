import AppKit
import BrowCore

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
    private var island: IslandController!
    private var menu: IslandMenu!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        settings = SettingsWindowController(model: model)
        // No Dock icon and no menu bar icon: a right-click on the island is the way to Settings and Quit.
        menu = IslandMenu(model: model, openSettings: { [weak self] in self?.settings.show() })
        island = IslandController(model: model, makeMenu: { [weak self] in self?.menu.make() ?? NSMenu() })

        model.pomodoro.onPhaseFinished = { [weak self] phase in
            guard let self else { return }
            let pomodoro = self.model.pomodoro
            if pomodoro.soundName != "None" { NSSound(named: pomodoro.soundName)?.play() }
            if pomodoro.peeksOnPhaseEnd { self.island.showPeek(.phaseFinished(phase)) }
        }
        // An event starting opens the island for a moment, without a sound.
        model.calendar.onEventStarted = { [weak self] event in
            guard let self, self.model.calendar.peeksOnStart else { return }
            self.island.showPeek(.eventStarted(event))
        }
    }

    /// Opening the app again, from Finder or Spotlight, shows the settings: there is nothing else to show.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}
