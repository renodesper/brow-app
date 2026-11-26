import XCTest
@testable import BrowCore

final class StatusLineHookTests: XCTestCase {
    private let capture = "/Users/me/Library/Application Support/Brow/claude-status.json"

    func testWrapsAndUnwrapsTheOwnersCommand() {
        let original = "~/.claude/statusline.sh --fancy # mine"
        let wrapped = StatusLineHook.command(wrapping: original, capturePath: capture)
        XCTAssertTrue(StatusLineHook.isOurs(wrapped))
        XCTAssertTrue(wrapped.contains("tee '\(capture)'"))
        XCTAssertEqual(StatusLineHook.unwrapped(wrapped), original)
    }

    func testWrappingNothingUnwrapsToNothing() {
        let wrapped = StatusLineHook.command(wrapping: nil, capturePath: capture)
        XCTAssertNil(StatusLineHook.unwrapped(wrapped))
    }

    func testACommandThatIsNotOursIsLeftAsItIs() {
        XCTAssertFalse(StatusLineHook.isOurs("echo hi"))
        XCTAssertEqual(StatusLineHook.unwrapped("echo hi"), "echo hi")
    }

    func testQuotesInThePathAreEscaped() {
        let wrapped = StatusLineHook.command(wrapping: nil, capturePath: "/tmp/it's/here.json")
        XCTAssertTrue(wrapped.contains(#"tee '/tmp/it'\''s/here.json'"#))
    }

    func testInstallAndUninstallRestoreTheSettings() throws {
        let folder = try TemporaryFolder()
        let before = #"{"model":"opus","statusLine":{"command":"echo hi","padding":0,"type":"command"}}"#
        try folder.write(before, to: "settings.json")
        let settings = folder.url.appendingPathComponent("settings.json")

        try StatusLineHook.install(settingsURL: settings, capturePath: capture)
        try StatusLineHook.install(settingsURL: settings, capturePath: capture)
        XCTAssertTrue(StatusLineHook.isInstalled(settingsURL: settings))
        XCTAssertEqual(try statusLine(in: settings)?["command"] as? String,
                       StatusLineHook.command(wrapping: "echo hi", capturePath: capture))

        try StatusLineHook.uninstall(settingsURL: settings)
        XCTAssertFalse(StatusLineHook.isInstalled(settingsURL: settings))
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(before.utf8)) as? NSDictionary
        XCTAssertEqual(after, expected)

        // The file as it was before the first change is kept beside it.
        let backup = try String(contentsOf: settings.appendingPathExtension("brow-backup"), encoding: .utf8)
        XCTAssertEqual(backup, before)
    }

    func testUninstallRemovesAStatusLineThatWasNotThereBefore() throws {
        let folder = try TemporaryFolder()
        try folder.write(#"{"model":"opus"}"#, to: "settings.json")
        let settings = folder.url.appendingPathComponent("settings.json")

        try StatusLineHook.install(settingsURL: settings, capturePath: capture)
        XCTAssertNotNil(try statusLine(in: settings))
        try StatusLineHook.uninstall(settingsURL: settings)
        XCTAssertNil(try statusLine(in: settings))
    }

    func testRefusesWhatItCannotRead() throws {
        let folder = try TemporaryFolder()
        try folder.write("// not json", to: "settings.json")
        XCTAssertThrowsError(try StatusLineHook.install(settingsURL: folder.url.appendingPathComponent("settings.json"),
                                                        capturePath: capture)) {
            XCTAssertEqual($0 as? StatusLineHook.Failure, .settingsUnreadable)
        }
        XCTAssertThrowsError(try StatusLineHook.install(settingsURL: folder.url.appendingPathComponent("gone/settings.json"),
                                                        capturePath: capture)) {
            XCTAssertEqual($0 as? StatusLineHook.Failure, .claudeCodeNotFound)
        }
    }

    private func statusLine(in settings: URL) throws -> [String: Any]? {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        return root?["statusLine"] as? [String: Any]
    }
}
