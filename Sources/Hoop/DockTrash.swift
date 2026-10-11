import AppKit
import ApplicationServices

/// Finds the Trash tile in the Dock through the Accessibility API.
enum DockTrash {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// The Trash tile's frame in Cocoa screen coordinates (origin at the bottom-left of the primary screen).
    static func frame() -> CGRect? {
        guard isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        for list in children(of: app) where string(list, kAXRoleAttribute) == kAXListRole {
            for item in children(of: list) where string(item, kAXSubroleAttribute) == "AXTrashDockItem" {
                guard let origin = point(item, kAXPositionAttribute), let size = size(item, kAXSizeAttribute) else { return nil }
                // Accessibility uses a top-left origin; flip it against the primary screen.
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                return CGRect(x: origin.x, y: primaryHeight - origin.y - size.height, width: size.width, height: size.height)
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(element, attribute), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(element, attribute), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        return (raw as! AXValue)
    }
}
