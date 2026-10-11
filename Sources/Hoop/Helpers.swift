import AppKit
import os

/// Key steps of a throw, readable with `log stream --predicate 'subsystem == "com.safa.hoop"'`.
enum Log {
    private static let logger = Logger(subsystem: "com.safa.hoop", category: "game")

    static func event(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

enum Palette {
    static let rim = NSColor(hex: 0x4A5AEF)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension NSAttributedString {
    /// System-font text for `SKLabelNode.attributedText` (font names like ".SFNS" don't work with `fontName`).
    static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
    }
}

extension String {
    /// "a-very-long-file-name.png" → "a-very-lo…name.png"
    func middleTruncated(to limit: Int) -> String {
        guard count > limit else { return self }
        let tail = (limit - 1) / 2
        return "\(prefix(limit - 1 - tail))…\(suffix(tail))"
    }
}
