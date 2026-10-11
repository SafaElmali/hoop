import QuickLookThumbnailing
import SpriteKit

/// A thrown file: its icon and name.
final class FileNode: Throwable {
    private static let iconSide: CGFloat = 50

    let url: URL

    private let icon = SKSpriteNode()

    init(url: URL) {
        self.url = url
        super.init()

        setIcon(Self.finderIcon(for: url))
        addChild(icon)

        // White name with a dark copy underneath, like desktop icon labels.
        let name = url.lastPathComponent.middleTruncated(to: 18)
        for (color, offset, z) in [(NSColor(white: 0, alpha: 0.6), CGFloat(-1), CGFloat(0.1)), (.white, 0, 0.2)] {
            let label = SKLabelNode()
            label.attributedText = .label(name, size: 11, weight: .medium, color: color)
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: -Self.radius - 9 + offset)
            label.zPosition = z
            addChild(label)
        }

        takeFlight()
        loadThumbnail()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tilts the icon with horizontal speed.
    override func updateLook() {
        let velocity = physicsBody?.velocity ?? .zero
        let tilt = max(-0.35, min(0.35, -velocity.dx / 1800))
        icon.zRotation += (tilt - icon.zRotation) * 0.25
    }

    private func setIcon(_ image: CGImage?) {
        guard let image else { return }
        icon.texture = SKTexture(cgImage: image)
        let scale = Self.iconSide / CGFloat(max(image.width, image.height))
        icon.size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    private static func finderIcon(for url: URL) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: iconSide * 2, height: iconSide * 2)
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            .cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Swaps the generic type icon for a Finder-style preview of the content when one exists.
    private func loadThumbnail() {
        let size = CGSize(width: Self.iconSide, height: Self.iconSide)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        request.iconMode = true
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.cgImage else { return }
            DispatchQueue.main.async { self?.setIcon(image) }
        }
    }
}
