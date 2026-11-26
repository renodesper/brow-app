import XCTest
@testable import BrowCore

final class AgendaTests: XCTestCase {
    private struct Event: Scheduled, Equatable {
        var name: String
        var start: Date
        var end: Date
    }

    private let nine = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, startsIn minutes: Double, lasting length: Double = 30) -> Event {
        let start = nine.addingTimeInterval(minutes * 60)
        return Event(name: name, start: start, end: start.addingTimeInterval(length * 60))
    }

    func testAnEventShowsFromFifteenMinutesBeforeUntilFiveAfter() {
        let events = [event("standup", startsIn: 60)]
        XCTAssertNil(Agenda.near(events, at: nine.addingTimeInterval(44 * 60)))
        XCTAssertEqual(Agenda.near(events, at: nine.addingTimeInterval(45 * 60))?.name, "standup")
        XCTAssertEqual(Agenda.near(events, at: nine.addingTimeInterval(64 * 60))?.name, "standup")
        XCTAssertNil(Agenda.near(events, at: nine.addingTimeInterval(65 * 60)))
    }

    func testAShortEventLeavesAsItEnds() {
        let events = [event("call", startsIn: 10, lasting: 2)]
        XCTAssertNotNil(Agenda.near(events, at: nine.addingTimeInterval(11 * 60)))
        XCTAssertNil(Agenda.near(events, at: nine.addingTimeInterval(12 * 60)))
    }

    func testTheOneAboutToStartWinsOverTheOneUnderWay() {
        let events = [event("started", startsIn: -2), event("soon", startsIn: 8), event("later", startsIn: 12)]
        XCTAssertEqual(Agenda.near(events, at: nine)?.name, "soon")
    }

    func testOfTwoUnderWayTheLatestWins() {
        let events = [event("first", startsIn: -4), event("second", startsIn: -1)]
        XCTAssertEqual(Agenda.near(events, at: nine)?.name, "second")
    }

    func testNextChangeWalksThroughShowingStartingAndLeaving() {
        let events = [event("standup", startsIn: 60)]
        var now = nine
        var changes: [Double] = []
        while let next = Agenda.nextChange(events, after: now) {
            changes.append(next.timeIntervalSince(nine) / 60)
            now = next
        }
        XCTAssertEqual(changes, [45, 60, 65])
    }

    func testNextChangeIsTheEarliestAmongEvents() {
        let events = [event("later", startsIn: 120), event("sooner", startsIn: 30)]
        XCTAssertEqual(Agenda.nextChange(events, after: nine), nine.addingTimeInterval(15 * 60))
        XCTAssertNil(Agenda.nextChange([Event](), after: nine))
    }

    func testCountdownRoundsMinutesUp() {
        XCTAssertEqual(Agenda.countdownText(to: nine.addingTimeInterval(15 * 60), at: nine), "in 15m")
        XCTAssertEqual(Agenda.countdownText(to: nine.addingTimeInterval(61), at: nine), "in 2m")
        XCTAssertEqual(Agenda.countdownText(to: nine.addingTimeInterval(1), at: nine), "in 1m")
        XCTAssertEqual(Agenda.countdownText(to: nine, at: nine), "Now")
        XCTAssertEqual(Agenda.countdownText(to: nine, at: nine.addingTimeInterval(90)), "Now")
    }

    func testTheLeadCanBeShorter() {
        let events = [event("review", startsIn: 10)]
        XCTAssertNil(Agenda.near(events, at: nine, lead: 5 * 60))
        XCTAssertEqual(Agenda.near(events, at: nine.addingTimeInterval(5 * 60), lead: 5 * 60)?.name, "review")
        XCTAssertEqual(Agenda.nextChange(events, after: nine, lead: 5 * 60), nine.addingTimeInterval(5 * 60))
    }
}
