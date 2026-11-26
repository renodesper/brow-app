import XCTest
@testable import BrowCore

final class MeetingLinkTests: XCTestCase {
    func testFindsAZoomLinkInNotes() {
        let notes = "Agenda below.\nJoin Zoom Meeting\nhttps://acme.zoom.us/j/123456789?pwd=abc\nPasscode: 1"
        XCTAssertEqual(MeetingLink.find(in: [nil, nil, notes])?.absoluteString,
                       "https://acme.zoom.us/j/123456789?pwd=abc")
    }

    func testFindsAMeetLinkInTheLocation() {
        XCTAssertEqual(MeetingLink.find(in: [nil, "https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com")
    }

    func testFindsATeamsLinkInTheEventURL() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0"
        XCTAssertEqual(MeetingLink.find(in: [link, nil, nil])?.host, "teams.microsoft.com")
    }

    func testFindsAWebexLink() {
        XCTAssertEqual(MeetingLink.find(in: ["Join: https://acme.webex.com/meet/jane"])?.host, "acme.webex.com")
    }

    func testTheEventURLWinsOverTheNotes() {
        let url = "https://meet.google.com/aaa-bbbb-ccc"
        let notes = "https://zoom.us/j/999"
        XCTAssertEqual(MeetingLink.find(in: [url, nil, notes])?.host, "meet.google.com")
    }

    func testOtherLinksAreSkippedForTheMeetingAfterThem() {
        let notes = "Slides: https://example.com/deck and the call https://zoom.us/j/42"
        XCTAssertEqual(MeetingLink.find(in: [notes])?.absoluteString, "https://zoom.us/j/42")
    }

    func testNoLinkMeansNoMeeting() {
        XCTAssertNil(MeetingLink.find(in: [nil, "Room 4", "Bring the laptop"]))
        XCTAssertNil(MeetingLink.find(in: []))
    }

    func testALookAlikeHostIsNotAMeeting() {
        XCTAssertNil(MeetingLink.find(in: ["https://zoom.us.example.com/j/1"]))
        XCTAssertNil(MeetingLink.find(in: ["https://notzoom.us/j/1"]))
    }

    func testAServiceHomePageAloneIsNotAMeeting() {
        XCTAssertNil(MeetingLink.find(in: ["https://zoom.us", "https://meet.google.com/"]))
    }

    func testAPlainHTTPLinkIsNotOpened() {
        XCTAssertNil(MeetingLink.find(in: ["http://zoom.us/j/1"]))
    }

    func testAnEventCanBeJoinedFromTenMinutesBeforeItsStartUntilItEnds() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(1800)
        XCTAssertFalse(MeetingLink.isJoinable(start: start, end: end, at: start.addingTimeInterval(-601)))
        XCTAssertTrue(MeetingLink.isJoinable(start: start, end: end, at: start.addingTimeInterval(-600)))
        XCTAssertTrue(MeetingLink.isJoinable(start: start, end: end, at: start.addingTimeInterval(900)))
        XCTAssertFalse(MeetingLink.isJoinable(start: start, end: end, at: end))
    }
}
