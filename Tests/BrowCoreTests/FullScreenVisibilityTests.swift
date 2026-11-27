import XCTest
@testable import BrowCore

final class FullScreenVisibilityTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func window(_ owner: String = "Safari", pid: Int32 = 100, layer: Int = 0,
                        bounds: CGRect? = nil, alpha: Double = 1) -> FullScreenDetection.Window {
        FullScreenDetection.Window(ownerPID: pid, ownerName: owner, layer: layer, bounds: bounds ?? display, alpha: alpha)
    }

    func testADisplaySizedWindowIsFullScreen() {
        XCTAssertTrue(FullScreenDetection.covers(display: display, topInset: 0, windows: [window()], ignoring: 1))
    }

    func testAMaximisedWindowBelowTheMenuBarIsNot() {
        let maximised = CGRect(x: 0, y: 38, width: 1512, height: 944)
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(bounds: maximised)], ignoring: 1))
    }

    func testAWindowOnAnotherDisplayIsNot() {
        let other = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(bounds: other)], ignoring: 1))
    }

    func testOurOwnWindowIsNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(pid: 1)], ignoring: 1))
    }

    func testTheWallpaperAndOtherBackgroundLayersAreNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("Dock", layer: -2_147_483_623)], ignoring: 1))
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(layer: -1)], ignoring: 1))
    }

    func testSystemOwnersAreNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("Dock", layer: 20)], ignoring: 1))
    }

    func testInvisibleWindowsAreNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(alpha: 0)], ignoring: 1))
    }

    func testAWindowJustAboveTheNormalLayerStillCounts() {
        XCTAssertTrue(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("Keynote", layer: 3)], ignoring: 1))
    }

    // Measured while the screen recorder ran: its overlays covered the display without any app in full screen.
    func testTheScreenRecordersOverlaysAreNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("screencapture", layer: 1498)], ignoring: 1))
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("Screenshot", layer: 24)], ignoring: 1))
    }

    func testAnyOverlayAtOrAboveTheMenuBarIsNot() {
        XCTAssertFalse(FullScreenDetection.covers(display: display, topInset: 0, windows: [window("Claude", layer: 1000)], ignoring: 1))
    }

    func testAHalfPointOffIsTheSameSize() {
        let nearly = CGRect(x: 0.4, y: 0, width: 1512, height: 982.5)
        XCTAssertTrue(FullScreenDetection.covers(display: display, topInset: 0, windows: [window(bounds: nearly)], ignoring: 1))
    }

    // Measured on a notched display of 2048 x 1330 points with a notch inset of 43.5.
    private let notched = CGRect(x: 0, y: 0, width: 2048, height: 1330)

    func testOnANotchedDisplayFullScreenFillsTheAreaBelowTheNotch() {
        let fullScreen = CGRect(x: 0, y: 44, width: 2048, height: 1286)
        XCTAssertTrue(FullScreenDetection.covers(display: notched, topInset: 43.5, windows: [window(bounds: fullScreen)], ignoring: 1))
    }

    func testOnANotchedDisplayAMaximisedWindowOnePointLowerIsNotFullScreen() {
        let filled = CGRect(x: 0, y: 45, width: 2048, height: 1285)
        XCTAssertFalse(FullScreenDetection.covers(display: notched, topInset: 43.5, windows: [window(bounds: filled)], ignoring: 1))
    }

    func testAWindowBelowTheNotchIsNotFullScreenOnADisplayWithoutOne() {
        let below = CGRect(x: 0, y: 44, width: 2048, height: 1286)
        XCTAssertFalse(FullScreenDetection.covers(display: notched, topInset: 0, windows: [window(bounds: below)], ignoring: 1))
    }

    func testNeverHidesOverFullScreenEvenForAlerts() {
        XCTAssertFalse(FullScreenMode.never.showsIsland(covered: true, peeking: true))
        XCTAssertTrue(FullScreenMode.never.showsIsland(covered: false, peeking: false))
    }

    func testAlertsShowsOnlyWhilePeeking() {
        XCTAssertTrue(FullScreenMode.alerts.showsIsland(covered: true, peeking: true))
        XCTAssertFalse(FullScreenMode.alerts.showsIsland(covered: true, peeking: false))
        XCTAssertTrue(FullScreenMode.alerts.showsIsland(covered: false, peeking: false))
    }

    func testAlwaysShowsEverywhere() {
        XCTAssertTrue(FullScreenMode.always.showsIsland(covered: true, peeking: false))
    }

    func testTheFullScreenFlagIsOnlyForWhereTheIslandMustShow() {
        XCTAssertFalse(FullScreenMode.never.needsFullScreenAuxiliary(peeking: true))
        XCTAssertFalse(FullScreenMode.alerts.needsFullScreenAuxiliary(peeking: false))
        XCTAssertTrue(FullScreenMode.alerts.needsFullScreenAuxiliary(peeking: true))
        XCTAssertTrue(FullScreenMode.always.needsFullScreenAuxiliary(peeking: false))
    }
}
