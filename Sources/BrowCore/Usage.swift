import Foundation

/// One limit of an AI subscription, such as a five-hour or a weekly window.
public struct UsageWindow: Equatable, Sendable {
    /// How long the window runs, like "5h" or "7d".
    public var label: String
    /// How much of it was used when it was read, from 0 to 1.
    public var used: Double
    /// When it starts over; nil if the tool didn't say.
    public var resetsAt: Date?

    public init(label: String, used: Double, resetsAt: Date? = nil) {
        self.label = label
        self.used = min(max(used, 0), 1)
        self.resetsAt = resetsAt
    }

    /// How much is used as of `now`: nothing once the window has started over since it was read.
    public func used(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { 0 } else { used }
    }
}

/// What one tool last reported about its limits.
public struct UsageReading: Equatable, Sendable {
    public var provider: String
    public var windows: [UsageWindow]
    /// When the tool wrote the numbers, which can be a while ago if it hasn't run since.
    public var measuredAt: Date?

    public init(provider: String, windows: [UsageWindow], measuredAt: Date? = nil) {
        self.provider = provider
        self.windows = windows
        self.measuredAt = measuredAt
    }
}

/// Reads the limits out of what each tool writes by itself. Input that carries no limits gives an empty list,
/// so a format change shows as "no data" rather than as wrong numbers.
public enum UsageParser {
    /// Claude Code's status-line input: `rate_limits.five_hour` and `rate_limits.seven_day`, each with
    /// `used_percentage` (0–100) and `resets_at`.
    public static func claudeWindows(statusLine data: Data) -> [UsageWindow] {
        guard let limits = try? decoder.decode(ClaudeStatus.self, from: data).rateLimits else { return [] }
        return [("5h", limits.fiveHour), ("7d", limits.sevenDay)].compactMap { label, window in
            window.map { UsageWindow(label: label, used: $0.usedPercentage / 100, resetsAt: $0.resetsAt?.date) }
        }
    }

    /// The newest `rate_limits` event in a Codex session log (one JSON object per line): `primary` and
    /// `secondary`, each with `used_percent` (0–100), `window_minutes` and `resets_at`.
    public static func codexWindows(sessionLog text: String) -> [UsageWindow] {
        // Walks back from the end, one mention of the limits at a time, without cutting the whole log into lines.
        var searchEnd = text.endIndex
        while let mention = text.range(of: "\"rate_limits\"", options: .backwards, range: text.startIndex..<searchEnd) {
            let lineStart = text[..<mention.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
            let lineEnd = text[mention.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            searchEnd = lineStart
            guard let event = try? decoder.decode(CodexEvent.self, from: Data(text[lineStart..<lineEnd].utf8)),
                  let limits = event.payload?.rateLimits ?? event.rateLimits else { continue }
            let windows = [limits.primary, limits.secondary].compactMap { window -> UsageWindow? in
                guard let window else { return nil }
                // Older logs give the seconds left as of the event instead of a date.
                let resetsAt = window.resetsAt?.date ?? window.resetsInSeconds.flatMap { seconds in
                    event.timestamp?.date?.addingTimeInterval(seconds)
                }
                return UsageWindow(label: label(forMinutes: window.windowMinutes ?? 0),
                                   used: window.usedPercent / 100, resetsAt: resetsAt)
            }
            if !windows.isEmpty { return windows }
        }
        return []
    }

    /// A window's length as written beside its bar: 300 minutes is "5h", 10080 is "7d".
    static func label(forMinutes minutes: Double) -> String {
        guard minutes > 0 else { return "" }
        return minutes >= 24 * 60 ? "\(Int((minutes / (24 * 60)).rounded()))d" : "\(Int((minutes / 60).rounded()))h"
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct ClaudeStatus: Decodable {
        var rateLimits: Limits?

        struct Limits: Decodable {
            var fiveHour: Window?
            var sevenDay: Window?
        }

        struct Window: Decodable {
            var usedPercentage: Double
            var resetsAt: Timestamp?
        }
    }

    private struct CodexEvent: Decodable {
        var timestamp: Timestamp?
        var payload: Payload?
        var rateLimits: Limits?

        struct Payload: Decodable {
            var rateLimits: Limits?
        }

        struct Limits: Decodable {
            var primary: Window?
            var secondary: Window?
        }

        struct Window: Decodable {
            var usedPercent: Double
            var windowMinutes: Double?
            var resetsAt: Timestamp?
            var resetsInSeconds: Double?
        }
    }

    /// A date written as Unix seconds or as ISO 8601. Anything else reads as no date rather than as an error,
    /// so an odd reset time doesn't cost the percentage beside it.
    private struct Timestamp: Decodable {
        var date: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                date = Date(timeIntervalSince1970: seconds)
            } else if let text = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                date = formatter.date(from: text)
                if date == nil {
                    formatter.formatOptions.insert(.withFractionalSeconds)
                    date = formatter.date(from: text)
                }
            }
        }
    }
}

/// Finds and reads the files the tools leave behind. Called only when the island opens, so nothing polls or
/// watches a folder in between.
public enum UsageFiles {
    /// The status-line input Claude Code last handed over (see `StatusLineHook`).
    public static func claudeReading(captureURL: URL) -> UsageReading? {
        guard let data = try? Data(contentsOf: captureURL) else { return nil }
        let windows = UsageParser.claudeWindows(statusLine: data)
        return windows.isEmpty ? nil : UsageReading(provider: "Claude", windows: windows,
                                                    measuredAt: modificationDate(of: captureURL))
    }

    /// The newest Codex session log that carries limits. Codex keeps them as
    /// `sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, so sorting names backwards walks from newest to oldest.
    /// - Parameter maxFiles: How many logs to try before giving up; a session that never got a reply has none.
    public static func codexReading(sessionsURL: URL, maxFiles: Int = 5) -> UsageReading? {
        var tried = 0
        for year in newestFirst(in: sessionsURL) {
            for month in newestFirst(in: year) {
                for day in newestFirst(in: month) {
                    for log in newestFirst(in: day) where log.pathExtension == "jsonl" {
                        guard tried < maxFiles else { return nil }
                        tried += 1
                        guard let text = tail(of: log) else { continue }
                        let windows = UsageParser.codexWindows(sessionLog: text)
                        if !windows.isEmpty {
                            return UsageReading(provider: "Codex", windows: windows,
                                                measuredAt: modificationDate(of: log))
                        }
                    }
                }
            }
        }
        return nil
    }

    /// The end of a file. Session logs grow to many megabytes, and only their last events matter.
    static func tail(of url: URL, bytes: UInt64 = 256 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: end > bytes ? end - bytes : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func newestFirst(in folder: URL) -> [URL] {
        let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: .skipsHiddenFiles)
        return (entries ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
