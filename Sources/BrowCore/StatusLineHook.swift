import Foundation

/// Lets Brow see Claude Code's usage limits without touching a login token.
///
/// Claude Code pipes a JSON report, limits included, into its status-line command. Connected, that command
/// becomes `tee <file> | ( the owner's own command )`: `tee` keeps a copy for the island and passes the input
/// on unchanged, so the status line looks as it did. If the island's folder is ever gone, `tee` fails quietly
/// and the owner's command still runs.
public enum StatusLineHook {
    public enum Failure: Error, Equatable {
        /// There is no Claude Code settings folder: Claude Code isn't installed.
        case claudeCodeNotFound
        /// The settings file isn't a JSON object, so it is left alone.
        case settingsUnreadable
    }

    /// A shell no-op that starts every command written here, so the island knows its own.
    static let marker = ": brow; "
    private static let opener = " | ( "
    /// On its own line, so a `#` comment ending the owner's command can't swallow it.
    private static let closer = "\n)"

    public static func command(wrapping original: String?, capturePath: String) -> String {
        let capture = marker + "tee '" + capturePath.replacingOccurrences(of: "'", with: #"'\''"#) + "' 2>/dev/null"
        guard let original, !original.isEmpty else { return capture + " >/dev/null" }
        return capture + opener + original + closer
    }

    public static func isOurs(_ command: String) -> Bool {
        command.hasPrefix(marker)
    }

    /// The owner's own command: what `command` wraps if it is one of ours (nil if it wraps nothing), and
    /// `command` itself otherwise.
    public static func unwrapped(_ command: String) -> String? {
        guard isOurs(command) else { return command }
        guard let start = command.range(of: opener), command.hasSuffix(closer) else { return nil }
        return String(command[start.upperBound...].dropLast(closer.count))
    }

    public static func isInstalled(settingsURL: URL) -> Bool {
        guard let settings = try? read(settingsURL) else { return false }
        return currentCommand(in: settings).map(isOurs) ?? false
    }

    /// Wraps the owner's status line. Safe to repeat: an already wrapped one is rewrapped, not wrapped twice.
    public static func install(settingsURL: URL, capturePath: String) throws {
        var settings = try read(settingsURL)
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        let original = currentCommand(in: settings).flatMap(unwrapped)
        statusLine["type"] = "command"
        statusLine["command"] = command(wrapping: original, capturePath: capturePath)
        settings["statusLine"] = statusLine
        try write(settings, to: settingsURL)
    }

    /// Puts the owner's status line back. A status line that isn't ours is left alone.
    public static func uninstall(settingsURL: URL) throws {
        var settings = try read(settingsURL)
        guard var statusLine = settings["statusLine"] as? [String: Any],
              let current = statusLine["command"] as? String, isOurs(current) else { return }
        if let original = unwrapped(current) {
            statusLine["command"] = original
            settings["statusLine"] = statusLine
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try write(settings, to: settingsURL)
    }

    private static func currentCommand(in settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else {
            // No settings file yet is fine, as long as Claude Code's folder is there.
            let folder = url.deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: folder) else { throw Failure.claudeCodeNotFound }
            return [:]
        }
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.settingsUnreadable
        }
        return settings
    }

    /// Writes the settings, keeping a copy of the file as it was before the first change next to it.
    private static func write(_ settings: [String: Any], to url: URL) throws {
        // A dotfiles setup links the file; the link is followed rather than replaced by a plain file.
        let target = url.resolvingSymlinksInPath()
        let backup = target.appendingPathExtension("brow-backup")
        let files = FileManager.default
        if files.fileExists(atPath: target.path), !files.fileExists(atPath: backup.path) {
            try files.copyItem(at: target, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
    }
}
