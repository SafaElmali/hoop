import AppKit
import QuickLookThumbnailing
import SpriteKit

/// Small builders for the promo's fake desktop.
enum Props {
    static func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> SKSpriteNode {
        let config = NSImage.SymbolConfiguration(pointSize: size * 2, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return SKSpriteNode() }
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: cgImage))
        sprite.size = CGSize(width: image.size.width / 2, height: image.size.height / 2)
        return sprite
    }

    static func image(_ image: NSImage, side: CGFloat) -> SKSpriteNode {
        var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return SKSpriteNode() }
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: cgImage))
        sprite.size = CGSize(width: side, height: side)
        return sprite
    }

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) -> SKLabelNode {
        let label = SKLabelNode()
        label.attributedText = .label(text, size: size, weight: weight, color: color)
        label.verticalAlignmentMode = .center
        return label
    }

    /// White text with a soft dark copy underneath, like desktop icon names.
    static func shadowedLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .medium) -> SKNode {
        let node = SKNode()
        let shade = label(text, size: size, weight: weight, color: NSColor(white: 0, alpha: 0.55))
        shade.position = CGPoint(x: 0, y: -1)
        let face = label(text, size: size, weight: weight)
        face.zPosition = 0.1
        node.addChild(shade)
        node.addChild(face)
        return node
    }

    static func pill(size: CGSize, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) -> SKShapeNode {
        let shape = SKShapeNode(rectOf: size, cornerRadius: radius)
        shape.fillColor = fill
        shape.strokeColor = stroke ?? .clear
        shape.lineWidth = stroke == nil ? 0 : 1
        return shape
    }

    /// The icon Finder would show: a QuickLook preview where there is one, else the type icon.
    static func fileIcon(_ url: URL, side: CGFloat) -> SKSpriteNode {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail)
        request.iconMode = true
        var preview: CGImage?
        let done = DispatchSemaphore(value: 0)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            preview = representation?.cgImage
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
        guard let cgImage = preview ?? NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: &rect, context: nil, hints: nil)
        else { return SKSpriteNode() }
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: cgImage))
        let scale = side / CGFloat(max(cgImage.width, cgImage.height))
        sprite.size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
        return sprite
    }

    /// A deep blue-to-pink wallpaper with soft glows.
    static func wallpaper(size: CGSize) -> SKSpriteNode {
        let scale: CGFloat = 2
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let base = CGGradient(colorsSpace: space, colors: [NSColor(hex: 0x101A4A).cgColor, NSColor(hex: 0x3A2A8C).cgColor, NSColor(hex: 0xB8457E).cgColor] as CFArray,
                              locations: [0, 0.55, 1])!
        context.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        let glows: [(CGPoint, CGFloat, NSColor)] = [
            (CGPoint(x: size.width * 0.78, y: size.height * 0.72), size.width * 0.45, NSColor(hex: 0xF0A3C8, alpha: 0.35)),
            (CGPoint(x: size.width * 0.15, y: size.height * 0.2), size.width * 0.4, NSColor(hex: 0x4F7BFF, alpha: 0.3)),
        ]
        for (center, radius, color) in glows {
            let glow = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
            context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: context.makeImage()!))
        sprite.size = size
        sprite.anchorPoint = .zero
        return sprite
    }

    static func appIcon(side: CGFloat) -> SKSpriteNode {
        let url = FileManager.default.temporaryDirectory.appending(path: "hoop-promo-icon.png")
        IconRenderer.write(to: url)
        return image(NSImage(contentsOf: url) ?? NSImage(), side: side)
    }
}

/// A file icon sitting on the desktop.
final class DesktopIcon: SKNode {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
        addChild(Props.fileIcon(url, side: 64))
        let name = Props.shadowedLabel(url.lastPathComponent.middleTruncated(to: 22), size: 12)
        name.position = CGPoint(x: 0, y: -44)
        addChild(name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
