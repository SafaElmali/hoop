import AppKit

/// Asks Finder to do things over Apple Events; macOS asks once for permission to control it.
/// Runs through osascript, so a first-time permission prompt doesn't block the game.
enum Finder {
    static func isOnDesktop(_ url: URL) -> Bool {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return false }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().path == desktop.resolvingSymlinksInPath().path
    }

    /// Moves a file to the Trash exactly like dragging it onto the Dock's Trash: Put Back works and
    /// Finder plays its trash sound. Calls back on the main queue with where the file went, or nil
    /// if Finder couldn't (for instance without permission to control it).
    static func trash(_ url: URL, completion: @escaping (URL?) -> Void) {
        run([
            "tell application \"Finder\" to set trashed to delete (POSIX file \"\(escaped(url.path(percentEncoded: false)))\" as alias)",
            "return POSIX path of (trashed as alias)",
        ]) { output in
            completion(output.map { URL(fileURLWithPath: $0) })
        }
    }

    /// Centres a desktop item's icon on `point` (Cocoa screen coordinates).
    static func moveDesktopIcon(of url: URL, to point: CGPoint) {
        // Finder's desktop coordinates start at the top-left of the main screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let position = "{\(Int(point.x.rounded())), \(Int((primaryHeight - point.y).rounded()))}"
        run(["tell application \"Finder\" to set desktop position of item \"\(escaped(url.lastPathComponent))\" of desktop to \(position)"])
    }

    /// Runs AppleScript `lines`; `completion` gets its output on the main queue, or nil if it failed.
    private static func run(_ lines: [String], completion: ((String?) -> Void)? = nil) {
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = lines.flatMap { ["-e", $0] }
        let output = Pipe(), errors = Pipe()
        osascript.standardOutput = output
        osascript.standardError = errors
        osascript.terminationHandler = { process in
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 {
                Log.event("Finder said no: \(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
            }
            let result = process.terminationStatus == 0 && !text.isEmpty ? text : nil
            DispatchQueue.main.async { completion?(result) }
        }
        do {
            try osascript.run()
        } catch {
            completion?(nil)
        }
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
