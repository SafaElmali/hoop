import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The "Shortcut…" window: shows the shoot mode shortcut and records a new one.
final class ShortcutWindow: NSObject, NSWindowDelegate {
    private let recorder: ShortcutRecorder
    private var window: NSWindow?

    /// `onChange` gets nil when recording starts, so typing the current shortcut records it instead of
    /// firing it, then the shortcut to use: the new one, or the old one again after a cancel.
    init(onChange: @escaping (Shortcut?) -> Void) {
        recorder = ShortcutRecorder(onChange: onChange)
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // Hoop has no Dock icon or app menu, so bring the app forward along with the window.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Switching to another app, or closing the window, stops recording so the shortcut comes back.
    func windowDidResignKey(_ notification: Notification) {
        recorder.cancel()
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingView(rootView: ShortcutView(recorder: recorder))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: content.fittingSize), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Hoop"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

/// Records the next key combination typed while the Shortcut window is key. Esc cancels.
@Observable
final class ShortcutRecorder {
    private(set) var shortcut = Shortcut.saved
    private(set) var isRecording = false
    /// Modifiers held so far while recording, like "⌃⌥".
    private(set) var held = ""
    /// The last key typed came without ⌃, ⌥ or ⌘.
    private(set) var needsModifier = false

    @ObservationIgnored private let onChange: (Shortcut?) -> Void
    @ObservationIgnored private var monitor: Any?

    init(onChange: @escaping (Shortcut?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        onChange(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    /// Stops recording and keeps the current shortcut.
    func cancel() {
        guard isRecording else { return }
        stop()
        onChange(shortcut)
    }

    func reset() {
        use(.standard)
    }

    private func handle(_ event: NSEvent) {
        held = Shortcut.symbols(for: event.modifierFlags)
        guard event.type == .keyDown, !event.isARepeat else { return }
        guard Int(event.keyCode) != kVK_Escape else { return cancel() }
        guard let shortcut = Shortcut(event: event) else {
            needsModifier = true
            NSSound.beep()
            return
        }
        use(shortcut)
    }

    private func use(_ shortcut: Shortcut) {
        stop()
        self.shortcut = shortcut
        Shortcut.saved = shortcut
        onChange(shortcut)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        held = ""
        needsModifier = false
    }
}

/// In the toast's style: the orange ball, a bold line and a quieter one, and the shortcut in a capsule.
private struct ShortcutView: View {
    let recorder: ShortcutRecorder

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shoot mode shortcut").font(.system(size: 13, weight: .semibold))
                    Text(hint).font(.system(size: 12)).foregroundStyle(recorder.needsModifier ? .orange : .secondary)
                }
                HStack(spacing: 10) {
                    Button(action: toggleRecording) {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 130, height: 26)
                            .background(.quaternary, in: Capsule())
                            .overlay(Capsule().strokeBorder(recorder.isRecording ? Color.orange : .clear, lineWidth: 2))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("Reset to \(Shortcut.standard.symbols)", action: recorder.reset)
                        .disabled(recorder.shortcut == .standard && !recorder.isRecording)
                }
            }
            .frame(width: 270, alignment: .leading)
        }
        .padding(20)
        .fixedSize()
    }

    private var label: String {
        guard recorder.isRecording else { return recorder.shortcut.symbols }
        return recorder.held.isEmpty ? "Type a shortcut…" : "\(recorder.held)…"
    }

    private var hint: String {
        if recorder.needsModifier { return "Use ⌃, ⌥ or ⌘ with the key" }
        return recorder.isRecording ? "Esc to cancel" : "Starts and stops shoot mode from any app"
    }

    private func toggleRecording() {
        recorder.isRecording ? recorder.cancel() : recorder.start()
    }
}
