import AppKit
import BrowCore
import Observation
import SwiftUI

/// Owns the island's window on one display: where it sits, how large it is, and how the pointer opens, closes,
/// swipes and right-clicks it. With several displays there is one of these for each.
///
/// One panel does everything. Its frame is the island's own frame, so it never takes a click meant for the menu
/// bar or the app below. It grows as soon as the island needs more room and shrinks only once the island has
/// finished shrinking, and the drawing hangs from the top center of the frame, so nothing moves on screen as the
/// frame changes.
@MainActor
final class IslandController {
    private let model: DisplayContext
    /// The display this island sits on, by its stable identity.
    let displayID: String
    private let panel: IslandPanel
    /// Its size never changes with the panel's: it is as large as the island ever gets, plus the overshoot room,
    /// and pinned to the top
    /// center, so resizing the panel cannot move the drawing for the frame before SwiftUI lays out again.
    private let host: NSHostingView<IslandView>
    /// Builds the right-click menu as it opens, so it always matches what is going on.
    private let makeMenu: () -> NSMenu
    private var pendingOpen: Task<Void, Never>?
    private var pendingClose: Task<Void, Never>?
    private var pendingShrink: Task<Void, Never>?
    private var pendingPeekEnd: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var eventMonitors: [Any] = []
    private var swipe = SwipeTracker()
    /// Whether the swipe in progress has already gone far enough to change screen, so the tap is felt once.
    private var passedCommit = false

    init(model: DisplayContext, displayID: String, makeMenu: @escaping () -> NSMenu) {
        self.model = model
        self.displayID = displayID
        self.makeMenu = makeMenu
        panel = IslandPanel()

        let hover = HoverView()
        panel.contentView = hover
        host = NSHostingView(rootView: IslandView(model: model, actions: IslandActions(
            open: {}, showScreen: { _ in }, endPeek: {})))
        // The panel's size is set here, never by SwiftUI's layout.
        host.sizingOptions = []
        // Fixed size, anchored to the top and centered: only the margins give way when the panel resizes.
        host.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        hover.addSubview(host)

        // Now that self is whole, the views get actions that reach it.
        host.rootView = IslandView(model: model, actions: IslandActions(
            open: { [weak self] in self?.setOpen(true) },
            showScreen: { [weak self] index in self?.showScreen(index) },
            endPeek: { [weak self] in self?.endPeek(after: .zero) }))
        hover.onHover = { [weak self] isInside in self?.pointerMoved(inside: isInside) }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
        installEventMonitors()
        layout()
        followSize()
        panel.orderFrontRegardless()
    }

    /// Takes the island off the screen and stops listening, for a display that was turned off or unplugged.
    func teardown() {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        pendingShrink?.cancel()
        pendingPeekEnd?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        panel.orderOut(nil)
    }

    /// Opens the island a little to show that something happened, like an event starting.
    func showPeek(_ peek: Peek, for duration: Duration = .seconds(5)) {
        // The open island shows it all already.
        guard !model.island.isOpen else { return }
        model.island.peek = peek
        endPeek(after: duration)
    }

    func showScreen(_ index: Int) {
        let count = model.preferences.screens.count
        let target = min(max(index, 0), count - 1)
        guard target != model.island.screenIndex else { return }
        model.island.screenIndex = target
        model.preferences.lastScreen = target
    }

    private var isPointerInside: Bool {
        // NSMouseInRect counts the top edge as inside: a pointer pushed against the top of the screen sits
        // exactly on it.
        NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
    }

    private func endPeek(after delay: Duration) {
        pendingPeekEnd?.cancel()
        pendingPeekEnd = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            // A peek under the pointer stays until the pointer leaves, unless a button in it ended it.
            if delay > .zero, self.isPointerInside { return }
            self.model.island.peek = nil
        }
    }

    private func pointerMoved(inside: Bool) {
        if inside {
            pendingClose?.cancel()
            if model.island.peek != nil {
                // The pointer holds a peek open, so its buttons can be reached.
                pendingPeekEnd?.cancel()
                return
            }
            guard !model.island.isOpen else { return }
            // The island grows a little while the pointer rests on it: it is about to open, or can be clicked.
            model.island.isAnticipating = true
            guard model.preferences.openMode == .hover else { return }
            // A wait, so a pointer only passing through on its way elsewhere doesn't open the island.
            pendingOpen?.cancel()
            let delay = model.preferences.hoverDelay
            pendingOpen = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.setOpen(true)
            }
        } else if !isPointerInside {
            // Checked against the frame itself, since resizing the panel under the pointer can report an exit
            // that never happened.
            pendingOpen?.cancel()
            model.island.isAnticipating = false
            if model.island.peek != nil { endPeek(after: .seconds(1)) }
            guard model.island.isOpen else { return }
            // A short grace, so brushing past the edge doesn't shut the island. Coming back cancels it, and the
            // pointer is checked again when it ends in case no "entered" event arrived.
            pendingClose?.cancel()
            pendingClose = Task { [weak self] in
                try? await Task.sleep(for: IslandLayout.closeGrace)
                guard !Task.isCancelled, let self, !self.isPointerInside else { return }
                self.setOpen(false)
            }
        }
    }

    private func setOpen(_ open: Bool) {
        guard model.island.isOpen != open else { return }
        model.island.isDragging = false
        model.island.dragOffset = 0
        model.island.isAnticipating = false
        if open {
            pendingPeekEnd?.cancel()
            model.island.peek = nil
            let preferences = model.preferences
            let screen = preferences.opensOnLastScreen ? preferences.lastScreen : 0
            model.island.screenIndex = min(max(screen, 0), preferences.screens.count - 1)
            // Read as it opens, so what it shows is current without anything polling in between.
            model.usage.refresh()
            model.calendar.refresh()
        }
        model.island.isOpen = open
    }

    // MARK: Clicks, right-clicks and swipes

    /// Local monitors see the events meant for this app's windows before they are handed out, also while
    /// another app is active. Each one ignores events for any window but the island's.
    private func installEventMonitors() {
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.showMenu(for: event)
            return nil
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            // A click opens the closed island. Once open, or while it peeks, clicks belong to the buttons.
            if self.model.mode == .closed { self.setOpen(true) }
            return event
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.scrolled(event)
            return event
        } as Any)
    }

    private func showMenu(for event: NSEvent) {
        guard let view = panel.contentView else { return }
        pendingOpen?.cancel()
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
    }

    /// A two-finger swipe on the open island drags the screen with the fingers, then moves one screen left or right
    /// or springs back when they lift.
    private func scrolled(_ event: NSEvent) {
        guard model.island.isOpen, model.preferences.screens.count > 1,
              event.momentumPhase.isEmpty else { return }
        let phase: SwipeTracker.Phase
        if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            // A mouse wheel has no phases; it isn't a swipe.
            return
        }
        // With natural scrolling the deltas already follow the fingers; without it they run the other way.
        let sign: Double = event.isDirectionInvertedFromDevice ? 1 : -1
        let index = model.island.screenIndex
        let outcome = swipe.add(fingersX: sign * Double(event.scrollingDeltaX),
                                fingersY: sign * Double(event.scrollingDeltaY), phase: phase,
                                time: event.timestamp, canGoNext: index < model.preferences.screens.count - 1,
                                canGoPrevious: index > 0, width: Double(model.islandSize.width))
        switch outcome {
        case .none:
            break
        case .drag(let offset):
            model.island.isDragging = true
            model.island.dragOffset = offset
            // A tap on the trackpad the moment the swipe has gone far enough to change screen on letting go.
            let isPastCommit = swipe.wouldCommit(canGoNext: index < model.preferences.screens.count - 1,
                                                 canGoPrevious: index > 0, width: Double(model.islandSize.width))
            if isPastCommit, !passedCommit {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            passedCommit = isPastCommit
        case .commit(let step):
            // The strip of screens slides on from where the fingers left it, to the new screen.
            passedCommit = false
            model.island.isDragging = false
            showScreen(index + step)
            model.island.dragOffset = 0
        case .cancel:
            passedCommit = false
            model.island.isDragging = false
            model.island.dragOffset = 0
        }
    }

    // MARK: The frame

    /// Fits the panel again whenever the island's size changes: opening, closing, peeking, another screen, or
    /// something starting or stopping beside the notch.
    private func followSize() {
        withObservationTracking {
            _ = model.islandSize
            // The custom size changes the island's size by way of the layout, so the layout is watched too.
            _ = model.preferences.matchesNotch
            _ = model.preferences.customWidth
            _ = model.preferences.customHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layout()
                self?.followSize()
            }
        }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first(where: { $0.displayUUID == displayID }) else { return }
        let notch = Self.notchRect(on: screen)
        let state = model.island
        // Whole, even sizes, so half of every width is a whole point and all frames share one center.
        let detectedSize = CGSize(width: (notch.width / 2).rounded(.up) * 2, height: notch.height.rounded(.up))
        if state.detectedNotch != detectedSize { state.detectedNotch = detectedSize }
        // Settings shows the notch's own size: the notched display's, or the first one's on a Mac without a notch.
        let hasNotchedScreen = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        if (screen.safeAreaInsets.top > 0 || !hasNotchedScreen), model.app.detectedNotch != detectedSize {
            model.app.detectedNotch = detectedSize
        }
        let preferences = model.preferences
        let resolved = NotchSizing.resolved(detectedWidth: Double(detectedSize.width),
                                            detectedHeight: Double(detectedSize.height),
                                            customWidth: preferences.matchesNotch ? nil : preferences.customWidth,
                                            customHeight: preferences.matchesNotch ? nil : preferences.customHeight)
        let notchSize = CGSize(width: resolved.width, height: resolved.height)
        if state.notch != notchSize { state.notch = notchSize }
        let hasPhysicalNotch = screen.safeAreaInsets.top > 0
        if state.hasPhysicalNotch != hasPhysicalNotch { state.hasPhysicalNotch = hasPhysicalNotch }

        // Grow at once, with room for the spring to overshoot, so the island never draws outside the window;
        // shrink to the exact size only once the spring has come to rest. The margin takes clicks until then.
        let target = model.islandSize
        let room = CGSize(width: target.width + 2 * IslandLayout.overshoot, height: target.height + IslandLayout.overshoot)
        let current = panel.frame.size
        let grown = CGSize(width: max(current.width, room.width), height: max(current.height, room.height))
        setFrame(size: grown, notch: notch, screen: screen)
        pendingShrink?.cancel()
        let settling = IslandLayout.settlingDuration(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        pendingShrink = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settling))
            guard !Task.isCancelled, let self else { return }
            self.setFrame(size: self.model.islandSize, notch: notch, screen: screen)
        }
    }

    private func setFrame(size: CGSize, notch: CGRect, screen: NSScreen) {
        let frame = CGRect(x: (notch.midX - size.width / 2).rounded(.down), y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        fitHost(notch: model.island.notch)
    }

    /// Gives the hosting view the size of the largest island, top centered in the panel. It only changes when
    /// the notch does; the panel resizing leaves it alone.
    private func fitHost(notch: CGSize) {
        let biggest = IslandLayout.size(mode: .open, notch: notch, glyphs: 3, layout: .four, hasDots: true)
        let largest = CGSize(width: biggest.width + 2 * IslandLayout.overshoot, height: biggest.height + IslandLayout.overshoot)
        let bounds = panel.contentView?.bounds ?? .zero
        let frame = CGRect(x: ((bounds.width - largest.width) / 2).rounded(.down), y: bounds.height - largest.height,
                           width: largest.width, height: largest.height)
        if host.frame != frame { host.frame = frame }
    }

    /// The notch in screen coordinates: what lies between the two menu bar areas beside the camera. On a screen
    /// without a notch, a notch-sized area at the top center.
    private static func notchRect(on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGRect(x: frame.minX + left.width, y: frame.maxY - inset,
                          width: frame.width - left.width - right.width, height: inset)
        }
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return CGRect(x: frame.midX - 90, y: frame.maxY - menuBarHeight, width: 180, height: menuBarHeight)
    }
}

/// A borderless panel above the menu bar, on every Space, that never takes focus from the app in use.
private final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // Set explicitly, even to its default: only then does the panel take the pointer across its whole
        // frame, clear pixels included. Its frame is the island's own, so that is exactly what is wanted.
        ignoresMouseEvents = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Reports the pointer entering and leaving, also while another app is active.
private final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
