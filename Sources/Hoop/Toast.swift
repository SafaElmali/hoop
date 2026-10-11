import AppKit
import SwiftUI

struct ToastAction {
    let title: String
    let handler: () -> Void
}

struct ToastContent {
    var title: String
    var subtitle: String
    var action: ToastAction?
}

/// A pill at the top of the screen. The panel is non-activating, so clicking Undo
/// doesn't pull focus away from whatever app you're in.
final class Toast {
    /// Shown again when a temporary message expires (the shoot mode hint).
    private var resting: ToastContent?
    private var isShowingResting = false
    private var expiry: DispatchWorkItem?
    private let panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        return panel
    }()

    /// Shows `content` until replaced, and comes back after any temporary message.
    func rest(_ content: ToastContent, on screen: NSScreen) {
        resting = content
        present(content, on: screen)
        isShowingResting = true
    }

    /// Swaps in a new resting message without cutting a temporary one short: it shows now if the
    /// resting message is up, else once the temporary one expires.
    func updateResting(_ content: ToastContent, on screen: NSScreen) {
        resting = content
        if isShowingResting { present(content, on: screen) }
    }

    /// Drops the resting message, hiding it if it's on screen (a temporary one plays out).
    func clearResting() {
        resting = nil
        if isShowingResting { hide() }
    }

    func show(_ content: ToastContent, on screen: NSScreen, for duration: TimeInterval) {
        present(content, on: screen)
        isShowingResting = false
        let expiry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let resting { rest(resting, on: screen) } else { hide() }
        }
        self.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: expiry)
    }

    private func present(_ content: ToastContent, on screen: NSScreen) {
        expiry?.cancel()
        let host = NSHostingView(rootView: ToastView(content: content))
        let size = host.fittingSize
        panel.contentView = host
        let visible = screen.visibleFrame
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height + 6, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    private func hide() {
        expiry?.cancel()
        isShowingResting = false
        panel.orderOut(nil)
    }
}

private struct ToastView: View {
    let content: ToastContent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title).font(.system(size: 13, weight: .semibold))
                Text(content.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let action = content.action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, content.action == nil ? 18 : 10)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(20) // room for the shadow
        .fixedSize()
    }
}
