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

    func testASavedStateSurvivesJSON() throws {
        var pomodoro = Pomodoro(settings: settings)
        pomodoro.start(at: start)
        _ = pomodoro.finishIfDue(at: pomodoro.endDate!, autoStartNext: false)
        pomodoro.start(at: start)
        let states = [Pomodoro(settings: settings).state, pomodoro.state]
        for state in states {
            let decoded = try JSONDecoder().decode(Pomodoro.State.self, from: JSONEncoder().encode(state))
            XCTAssertEqual(decoded, state)
        }
    }

    func testARunningPhaseCarriesOnAfterARelaunch() {
        var before = Pomodoro(settings: settings)
        before.start(at: start)
        var after = Pomodoro(settings: settings)
        after.restore(before.state, at: start.addingTimeInterval(600))
        XCTAssertTrue(after.isRunning)
        XCTAssertEqual(after.endDate, before.endDate)
        XCTAssertEqual(after.remaining(at: start.addingTimeInterval(600)), 900)
    }

    func testAPausedPhaseKeepsItsTimeAfterARelaunch() {
        var before = Pomodoro(settings: settings)
        before.start(at: start)
        before.pause(at: start.addingTimeInterval(500))
        var after = Pomodoro(settings: settings)
        after.restore(before.state, at: start.addingTimeInterval(99_999))
        XCTAssertFalse(after.isRunning)
        XCTAssertEqual(after.remaining(at: start.addingTimeInterval(99_999)), 1000)
    }

    func testAPhaseThatEndedWhileClosedIsFinishedButNotStartedAgain() {
        var before = Pomodoro(settings: settings)
        before.start(at: start)
        var after = Pomodoro(settings: settings)
        after.restore(before.state, at: start.addingTimeInterval(5000))
        // Focus ran out: it counts, the short break is next, and it waits to be started.
        XCTAssertEqual(after.phase, .shortBreak)
        XCTAssertEqual(after.completedFocusRounds, 1)
        XCTAssertFalse(after.isActive)
    }

    func testAWaitingPhaseIsRestoredWhereItStood() {
        var before = Pomodoro(settings: settings)
        before.start(at: start)
        _ = before.finishIfDue(at: before.endDate!, autoStartNext: false)
        var after = Pomodoro(settings: settings)
        after.restore(before.state, at: start.addingTimeInterval(99_999))
        XCTAssertEqual(after.state, before.state)
        XCTAssertEqual(after.phase, .shortBreak)
    }

    func testClockTextRoundsUp() {
        XCTAssertEqual(Pomodoro.clockText(1500), "25:00")
        XCTAssertEqual(Pomodoro.clockText(1499.2), "25:00")
        XCTAssertEqual(Pomodoro.clockText(6.5), "0:07")
        XCTAssertEqual(Pomodoro.clockText(0), "0:00")
    }
}
