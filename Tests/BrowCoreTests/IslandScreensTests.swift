import XCTest
@testable import BrowCore

final class IslandScreensTests: XCTestCase {
    func testAScreenHoldsOneWidgetPerSlot() {
        XCTAssertEqual(IslandScreen(layout: .two, widgets: [.usage]).widgets, [.usage, .calendar])
        XCTAssertEqual(IslandScreen(layout: .one, widgets: [.pomodoro, .usage]).widgets, [.pomodoro])
        XCTAssertEqual(IslandScreen(layout: .four, widgets: [.usage, .usage]).widgets,
                       [.usage, .calendar, .pomodoro, .keepAwake])
    }

    func testChangingTheLayoutKeepsWhatFits() {
        var screen = IslandScreen(layout: .four, widgets: [.keepAwake, .usage, .calendar, .pomodoro])
        screen.setLayout(.two)
        XCTAssertEqual(screen.widgets, [.keepAwake, .usage])
        screen.setLayout(.four)
        XCTAssertEqual(screen.widgets, [.keepAwake, .usage, .calendar, .pomodoro])
    }

    func testPickingAWidgetThatIsAlreadyShownSwapsTheTwo() {
        var screen = IslandScreen(layout: .two, widgets: [.calendar, .pomodoro])
        screen.setWidget(.calendar, at: 1)
        XCTAssertEqual(screen.widgets, [.pomodoro, .calendar])
        screen.setWidget(.usage, at: 0)
        XCTAssertEqual(screen.widgets, [.usage, .calendar])
        screen.setWidget(.usage, at: 5)
        XCTAssertEqual(screen.widgets, [.usage, .calendar])
    }

    func testScreensSurviveSavingAndReading() {
        let screens = IslandScreens.defaults
        XCTAssertEqual(IslandScreens.decode(IslandScreens.encode(screens)), screens)
    }

    func testUnreadableOrEmptyScreensFallBackToTheDefaults() {
        XCTAssertEqual(IslandScreens.decode(nil).map(\.widgets), IslandScreens.defaults.map(\.widgets))
        XCTAssertEqual(IslandScreens.decode(Data("[]".utf8)).map(\.widgets), IslandScreens.defaults.map(\.widgets))
        XCTAssertEqual(IslandScreens.decode(Data("nonsense".utf8)).count, 3)
    }

    func testSavedScreensWithTooFewWidgetsAreFilledIn() throws {
        let json = #"[{"layout":"two","widgets":["usage"]}]"#
        let screens = IslandScreens.decode(Data(json.utf8))
        XCTAssertEqual(screens.first?.widgets, [.usage, .calendar])
    }

    func testTitles() {
        XCTAssertEqual(IslandScreen(layout: .two, widgets: [.calendar, .pomodoro]).title, "Calendar + Pomodoro")
        XCTAssertEqual(IslandScreen(layout: .four, widgets: []).title, "All four")
    }

    func testASwipeMovesOneScreenOnce() {
        var tracker = SwipeTracker()
        XCTAssertEqual(tracker.add(fingersX: 0, fingersY: 0, phase: .began), 0)
        XCTAssertEqual(tracker.add(fingersX: -20, fingersY: 2, phase: .changed), 0)
        XCTAssertEqual(tracker.add(fingersX: -20, fingersY: 2, phase: .changed), 1)
        XCTAssertEqual(tracker.add(fingersX: -200, fingersY: 0, phase: .changed), 0)
        XCTAssertEqual(tracker.add(fingersX: 0, fingersY: 0, phase: .ended), 0)
        XCTAssertEqual(tracker.add(fingersX: 0, fingersY: 0, phase: .began), 0)
        XCTAssertEqual(tracker.add(fingersX: 50, fingersY: 0, phase: .changed), -1)
    }

    func testAMostlyVerticalSwipeMovesNothing() {
        var tracker = SwipeTracker()
        _ = tracker.add(fingersX: 0, fingersY: 0, phase: .began)
        XCTAssertEqual(tracker.add(fingersX: 40, fingersY: 60, phase: .changed), 0)
    }
}
