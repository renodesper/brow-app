// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Brow",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no UI: the pomodoro cycle, usage parsing, the Claude Code status-line hook.
        .target(name: "BrowCore"),
        // The notch app itself: AppKit owns the window, SwiftUI draws inside it.
        .executableTarget(name: "Brow", dependencies: ["BrowCore"]),
        .testTarget(name: "BrowCoreTests", dependencies: ["BrowCore"]),
    ]
)
