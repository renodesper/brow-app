import Foundation

/// Finds the link that joins a video call in the text of a calendar event.
///
/// Only the big services are recognised, and only by their real host: `zoom.us.example.com` is not Zoom.
public enum MeetingLink {
    /// Hosts of the services, each matched exactly or as the end of a longer host (`acme.zoom.us`).
    private static let hosts = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                "webex.com"]

    /// The first meeting link in the texts, looked at in order: an event's own URL first, then its location,
    /// then its notes. A text that has no link, or only other links, is skipped.
    public static func find(in texts: [String?]) -> URL? {
        for case let text? in texts {
            for url in links(in: text) where isMeeting(url) { return url }
        }
        return nil
    }

    /// How long before its start a call can be joined.
    public static let joinLead: TimeInterval = 10 * 60

    /// Whether a Join button belongs on an event at `now`: from a little before it starts until it ends.
    public static func isJoinable(start: Date, end: Date, at now: Date) -> Bool {
        now >= start.addingTimeInterval(-joinLead) && now < end
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        // The bare home page of a service is not a meeting.
        guard url.path.count > 1 else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
