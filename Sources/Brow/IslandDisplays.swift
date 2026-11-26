import AppKit
import CoreGraphics
import Observation

extension NSScreen {
    /// A stable identity for the display, kept across unplugging and restarts (the display number is not).
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// One island for each display the owner has it on. They share every model, so timers, events and settings
/// match; each keeps its own open state, peek and screen.
@MainActor
final class IslandDisplays {
    private let app: AppModel
    private let makeMenu: () -> NSMenu
    private var controllers: [String: IslandController] = [:]
    private var screenObserver: NSObjectProtocol?

    init(app: AppModel, makeMenu: @escaping () -> NSMenu) {
        self.app = app
        self.makeMenu = makeMenu
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        reconcile()
        followPreference()
    }

    /// Opens every island a little, so the moment is seen whichever display the owner is looking at.
    func showPeek(_ peek: Peek, for duration: Duration = .seconds(5)) {
        for controller in controllers.values { controller.showPeek(peek, for: duration) }
    }

    /// Puts an island on each connected display it is turned on for, and takes the rest away.
    private func reconcile() {
        let wanted = Set(NSScreen.screens.compactMap(\.displayUUID).filter { app.preferences.showsIsland(onDisplay: $0) })
        for (id, controller) in controllers where !wanted.contains(id) {
            controller.teardown()
            controllers[id] = nil
        }
        for id in wanted where controllers[id] == nil {
            controllers[id] = IslandController(model: DisplayContext(app: app), displayID: id, makeMenu: makeMenu)
        }
    }

    private func followPreference() {
        withObservationTracking {
            _ = app.preferences.hiddenDisplays
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.followPreference()
            }
        }
    }
}
