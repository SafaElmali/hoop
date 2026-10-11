import AppKit

/// Moves desktop icons by asking Finder over Apple Events; macOS asks once for permission.
enum Finder {
    static func isOnDesktop(_ url: URL) -> Bool {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return false }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().path == desktop.resolvingSymlinksInPath().path
    }

    /// Centres a desktop item's icon on `point` (Cocoa screen coordinates).
    static func moveDesktopIcon(of url: URL, to point: CGPoint) {
        // Finder's desktop coordinates start at the top-left of the main screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let name = url.lastPathComponent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let position = "{\(Int(point.x.rounded())), \(Int((primaryHeight - point.y).rounded()))}"
        // osascript runs on its own, so a first-time permission prompt doesn't block the game.
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", "tell application \"Finder\" to set desktop position of item \"\(name)\" of desktop to \(position)"]
        osascript.standardError = FileHandle.nullDevice
        try? osascript.run()
    }
}
