import Foundation
import BrowCore
import Observation

/// The AI tools' usage limits, read from the files the tools write by themselves.
///
/// Nothing polls and nothing watches: the files are read when the island opens, off the main thread. No login
/// token is read and no network request is made.
@MainActor
@Observable
final class UsageModel {
    private(set) var readings: [UsageReading] = []
    /// When the files were last read.
    private(set) var lastRead: Date?

    var readsCodex: Bool {
        didSet {
            defaults.set(readsCodex, forKey: Key.readsCodex)
            refresh()
        }
    }

    /// Whether a limit at 80% or more is drawn in amber.
    var highlightsHighUse: Bool {
        didSet { defaults.set(highlightsHighUse, forKey: Key.highlights) }
    }

    var showsResetTimes: Bool {
        didSet { defaults.set(showsResetTimes, forKey: Key.resets) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        readsCodex = defaults.bool(Key.readsCodex, default: true)
        highlightsHighUse = defaults.bool(Key.highlights, default: true)
        showsResetTimes = defaults.bool(Key.resets, default: true)
    }

    /// Whether Claude Code's status line hands its limits over (see `StatusLineHook`). Read from Claude Code's
    /// settings each time, so it is right even if they were edited by hand.
    var isClaudeConnected: Bool {
        StatusLineHook.isInstalled(settingsURL: Paths.claudeSettings)
    }

    func refresh() {
        let readsCodex = readsCodex
        Task {
            readings = await Task.detached(priority: .utility) {
                [UsageFiles.claudeReading(captureURL: Paths.claudeCapture),
                 readsCodex ? UsageFiles.codexReading(sessionsURL: Paths.codexSessions) : nil].compactMap { $0 }
            }.value
            lastRead = Date()
        }
    }

    /// Connects or disconnects Claude Code's status line. Throws `StatusLineHook.Failure` if it can't.
    func setClaudeConnected(_ connect: Bool) throws {
        guard connect != isClaudeConnected else { return }
        if connect {
            try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try StatusLineHook.install(settingsURL: Paths.claudeSettings, capturePath: Paths.claudeCapture.path)
        } else {
            try StatusLineHook.uninstall(settingsURL: Paths.claudeSettings)
            try? FileManager.default.removeItem(at: Paths.claudeCapture)
        }
        refresh()
    }

    private enum Key {
        static let readsCodex = "usage.readsCodex"
        static let highlights = "usage.highlightsHighUse"
        static let resets = "usage.showsResetTimes"
    }

    private enum Paths {
        static let home = FileManager.default.homeDirectoryForCurrentUser
        static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brow")
        static let claudeCapture = support.appendingPathComponent("claude-status.json")
        static let claudeSettings = home.appendingPathComponent(".claude/settings.json")
        static let codexSessions = home.appendingPathComponent(".codex/sessions")
    }
}
