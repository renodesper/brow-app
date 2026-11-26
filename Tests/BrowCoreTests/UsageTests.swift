import XCTest
@testable import BrowCore

final class UsageTests: XCTestCase {
    func testReadsClaudeLimitsFromStatusLineInput() {
        let input = """
        {"session_id":"abc","model":{"display_name":"Opus"},
         "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1800000000},
                        "seven_day":{"used_percentage":7,"resets_at":"2027-01-15T08:00:00Z"}}}
        """
        let windows = UsageParser.claudeWindows(statusLine: Data(input.utf8))
        XCTAssertEqual(windows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(windows[0].used, 0.425, accuracy: 0.0001)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNotNil(windows[1].resetsAt)
    }

    func testClaudeInputWithoutLimitsGivesNothing() {
        XCTAssertEqual(UsageParser.claudeWindows(statusLine: Data(#"{"session_id":"abc"}"#.utf8)), [])
        XCTAssertEqual(UsageParser.claudeWindows(statusLine: Data("not json".utf8)), [])
    }

    func testReadsTheNewestCodexLimits() {
        let log = """
        {"timestamp":"2026-11-23T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1800000000}}}}
        {"timestamp":"2026-11-23T02:00:00.000Z","type":"response_item","payload":{"type":"message"}}
        {"timestamp":"2026-11-23T03:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":55,"window_minutes":299,"resets_at":1800000000},"secondary":{"used_percent":81.5,"window_minutes":10080,"resets_in_seconds":3600}}}}
        {"timestamp":"2026-11-23T03:00:01.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":null}}
        {"timestamp":"2026-11-23T03:00:02.000Z","type":"event_msg","payload":{"rate_limits":{"primary":{"used_per
        """
        let windows = UsageParser.codexWindows(sessionLog: log)
        XCTAssertEqual(windows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(windows[0].used, 0.55, accuracy: 0.0001)
        XCTAssertEqual(windows[1].used, 0.815, accuracy: 0.0001)
        // Seconds left count from the event's own time.
        let event = ISO8601DateFormatter().date(from: "2026-11-23T03:00:00Z")!
        XCTAssertEqual(windows[1].resetsAt, event.addingTimeInterval(3600))
    }

    func testAWindowThatStartedOverReadsEmpty() {
        let reset = Date(timeIntervalSince1970: 2_000)
        let window = UsageWindow(label: "5h", used: 0.9, resetsAt: reset)
        XCTAssertEqual(window.used(at: reset.addingTimeInterval(-1)), 0.9)
        XCTAssertEqual(window.used(at: reset), 0)
    }

    func testUsageIsKeptBetweenZeroAndOne() {
        XCTAssertEqual(UsageWindow(label: "5h", used: 1.4).used, 1)
        XCTAssertEqual(UsageWindow(label: "5h", used: -0.2).used, 0)
    }

    func testFindsTheNewestCodexLogWithLimits() throws {
        let sessions = try TemporaryFolder()
        let line = #"{"payload":{"rate_limits":{"primary":{"used_percent":USED,"window_minutes":300}}}}"#
        try sessions.write(line.replacingOccurrences(of: "USED", with: "20"), to: "2026/11/22/rollout-2026-11-22T10-00-00-a.jsonl")
        try sessions.write(line.replacingOccurrences(of: "USED", with: "30"), to: "2026/11/23/rollout-2026-11-23T09-00-00-b.jsonl")
        // The newest session never got a reply, so it carries no limits.
        try sessions.write(#"{"payload":{"type":"message"}}"#, to: "2026/11/23/rollout-2026-11-23T11-00-00-c.jsonl")

        let reading = UsageFiles.codexReading(sessionsURL: sessions.url)
        XCTAssertEqual(reading?.provider, "Codex")
        XCTAssertEqual(reading?.windows.first?.used ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertNil(UsageFiles.codexReading(sessionsURL: sessions.url.appendingPathComponent("missing")))
    }

    func testReadsOnlyTheEndOfALongFile() throws {
        let folder = try TemporaryFolder()
        try folder.write(String(repeating: "x", count: 5000) + "END", to: "big.txt")
        XCTAssertEqual(UsageFiles.tail(of: folder.url.appendingPathComponent("big.txt"), bytes: 10), "xxxxxxxEND")
    }
}

/// A folder that removes itself when the test is done with it.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("brow-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
}
