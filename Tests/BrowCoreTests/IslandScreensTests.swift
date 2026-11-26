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

    /// Runs a swipe of the given moves, each `(x, y, seconds since the start)`, and returns every outcome.
    private func swipe(_ moves: [(Double, Double, Double)], next: Bool = true, previous: Bool = true,
                       width: Double = 600) -> [SwipeTracker.Outcome] {
        var tracker = SwipeTracker()
        var outcomes = [tracker.add(fingersX: 0, fingersY: 0, phase: .began, time: 0,
                                    canGoNext: next, canGoPrevious: previous, width: width)]
        for move in moves {
            outcomes.append(tracker.add(fingersX: move.0, fingersY: move.1, phase: .changed, time: move.2,
                                        canGoNext: next, canGoPrevious: previous, width: width))
        }
        outcomes.append(tracker.add(fingersX: 0, fingersY: 0, phase: .ended, time: 10,
                                    canGoNext: next, canGoPrevious: previous, width: width))
        return outcomes
    }

    func testTheScreenFollowsTheFingersOnceTheSwipeIsHorizontal() {
        let outcomes = swipe([(-3, 0, 0.1), (-5, 1, 0.2), (-20, 1, 0.3)])
        XCTAssertEqual(outcomes[1], .none)
        XCTAssertEqual(outcomes[2], .drag(-8))
        XCTAssertEqual(outcomes[3], .drag(-28))
    }

    func testReleasingPastAQuarterOfTheWidthMovesToTheNextScreen() {
        XCTAssertEqual(swipe([(-100, 0, 0.5), (-60, 0, 1.5)]).last, .commit(1))
        XCTAssertEqual(swipe([(100, 0, 0.5), (60, 0, 1.5)]).last, .commit(-1))
    }

    func testReleasingAShortSlowSwipeSpringsBack() {
        XCTAssertEqual(swipe([(-40, 0, 0.5), (-20, 0, 1.5)]).last, .cancel)
    }

    func testAShortFastFlickStillMovesAScreen() {
        XCTAssertEqual(swipe([(-10, 0, 0.01), (-30, 0, 0.03)]).last, .commit(1))
    }

    func testAFlickBackTowardTheStartDoesNotMoveAScreen() {
        // Dragged left, then flicked quickly the other way: it ends short and against the flick.
        XCTAssertEqual(swipe([(-30, 0, 0.5), (15, 0, 0.51)]).last, .cancel)
    }

    func testAMostlyVerticalSwipeNeverMovesOrDrags() {
        let outcomes = swipe([(10, 40, 0.1), (200, 10, 0.2)])
        XCTAssertEqual(outcomes, [.none, .none, .none, .none])
    }

    func testDraggingTowardNoScreenResistsAndNeverCommits() {
        let outcomes = swipe([(-50, 0, 0.1), (-500, 0, 0.2)], next: false)
        guard case .drag(let small) = outcomes[1], case .drag(let large) = outcomes[2] else {
            return XCTFail("expected drags, got \(outcomes)")
        }
        XCTAssertLessThan(small, 0)
        XCTAssertLessThan(abs(small), 50)
        XCTAssertLessThan(large, small)
        XCTAssertLessThan(abs(large), 0.2 * 600)
        XCTAssertEqual(outcomes.last, .cancel)
    }

    func testEachSwipeStartsFresh() {
        var tracker = SwipeTracker()
        _ = tracker.add(fingersX: 0, fingersY: 0, phase: .began)
        _ = tracker.add(fingersX: -300, fingersY: 0, phase: .changed, time: 0.5)
        XCTAssertEqual(tracker.add(fingersX: 0, fingersY: 0, phase: .ended, time: 1), .commit(1))
        XCTAssertEqual(tracker.add(fingersX: 0, fingersY: 0, phase: .ended, time: 2), .none)
        _ = tracker.add(fingersX: 0, fingersY: 0, phase: .began)
        XCTAssertEqual(tracker.add(fingersX: 10, fingersY: 0, phase: .changed, time: 0.5), .drag(10))
    }
}
