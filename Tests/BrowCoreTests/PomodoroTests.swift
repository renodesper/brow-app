import XCTest
@testable import BrowCore

final class PomodoroTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let settings = Pomodoro.Settings(focus: 1500, shortBreak: 300, longBreak: 900, roundsUntilLongBreak: 2)

    func testWaitsAtFullLengthUntilStarted() {
        let pomodoro = Pomodoro(settings: settings)
        XCTAssertFalse(pomodoro.isActive)
        XCTAssertEqual(pomodoro.remaining(at: start), 1500)
    }

    func testCountsDownAgainstTheWallClock() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        XCTAssertEqual(pomodoro.remaining(at: start.addingTimeInterval(100)), 1400)
        XCTAssertEqual(pomodoro.remaining(at: start.addingTimeInterval(9999)), 0)
    }

    func testPauseKeepsTheTimeLeft() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        pomodoro.pause(at: start.addingTimeInterval(500))
        XCTAssertEqual(pomodoro.remaining(at: start.addingTimeInterval(5000)), 1000)
        pomodoro.start(at: start.addingTimeInterval(5000))
        XCTAssertEqual(pomodoro.endDate, start.addingTimeInterval(6000))
    }

    func testNothingFinishesEarly() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        XCTAssertNil(pomodoro.finishIfDue(at: start.addingTimeInterval(1499), autoStartNext: true))
        XCTAssertEqual(pomodoro.phase, .focus)
    }

    func testLongBreakFollowsEveryFewFocusRounds() {
        var pomodoro = Pomodoro(settings: settings)
        var now = start
        var phases: [Pomodoro.Phase] = []
        for _ in 0..<6 {
            pomodoro.start(at: now)
            now = pomodoro.endDate!
            phases.append(pomodoro.finishIfDue(at: now, autoStartNext: false)!)
        }
        XCTAssertEqual(phases, [.focus, .shortBreak, .focus, .longBreak, .focus, .shortBreak])
        XCTAssertEqual(pomodoro.completedFocusRounds, 3)
    }

    func testAutoStartRunsTheNextPhaseFromNow() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        // Found out late, as after sleep: the break starts when it is noticed, not when focus ended.
        let late = start.addingTimeInterval(2000)
        XCTAssertEqual(pomodoro.finishIfDue(at: late, autoStartNext: true), .focus)
        XCTAssertEqual(pomodoro.phase, .shortBreak)
        XCTAssertEqual(pomodoro.endDate, late.addingTimeInterval(300))
    }

    func testSkippedFocusDoesNotCount() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        pomodoro.skip()
        XCTAssertEqual(pomodoro.phase, .shortBreak)
        XCTAssertEqual(pomodoro.completedFocusRounds, 0)
        XCTAssertFalse(pomodoro.isActive)
    }

    func testRoundNumberStaysThroughItsBreak() {
        var pomodoro = Pomodoro(settings: settings)
        XCTAssertEqual(pomodoro.currentRound, 1)
        pomodoro.start(at: start)
        _ = pomodoro.finishIfDue(at: pomodoro.endDate!, autoStartNext: false)
        XCTAssertEqual(pomodoro.currentRound, 1)
        pomodoro.skip()
        XCTAssertEqual(pomodoro.currentRound, 2)
    }

    func testResetGoesBackToTheFirstRound() {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        _ = pomodoro.finishIfDue(at: pomodoro.endDate!, autoStartNext: true)
        pomodoro.reset()
        XCTAssertEqual(pomodoro, Pomodoro(settings: settings))
    }

    func testClockTextRoundsUp() {
        XCTAssertEqual(Pomodoro.clockText(1500), "25:00")
        XCTAssertEqual(Pomodoro.clockText(1499.2), "25:00")
        XCTAssertEqual(Pomodoro.clockText(6.5), "0:07")
        XCTAssertEqual(Pomodoro.clockText(0), "0:00")
    }
}
