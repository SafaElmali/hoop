import AppKit

if let flag = CommandLine.arguments.firstIndex(of: "--render-icon"), flag + 1 < CommandLine.arguments.count {
    IconRenderer.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
