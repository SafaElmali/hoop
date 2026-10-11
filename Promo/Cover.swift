import AppKit
import SpriteKit

/// The repo's cover image: the Trash as a basket with a file arcing in, and the name.
enum Cover {
    static let size = CGSize(width: 1280, height: 640)

    static func render(to url: URL) throws {
        let files = try PromoFiles()
        let scene = SKScene(size: size)
        scene.scaleMode = .fill
        let wallpaper = Props.wallpaper(size: size)
        wallpaper.zPosition = -100
        scene.addChild(wallpaper)

        let basket = BasketNode(side: 360, isFull: false)
        basket.position = CGPoint(x: 975, y: 36)
        scene.addChild(basket)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 250, height: 24))
        shadow.fillColor = NSColor(white: 0, alpha: 0.28)
        shadow.lineWidth = 0
        shadow.position = CGPoint(x: 975, y: 40)
        shadow.zPosition = -1
        scene.addChild(shadow)

        // A file arcing in, with a fading trail, and one already dropping through the opening.
        let trail: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 640, y: 330), 0.12, 0.7), (CGPoint(x: 720, y: 440), 0.2, 0.8),
            (CGPoint(x: 810, y: 510), 0.32, 0.9), (CGPoint(x: 900, y: 535), 1, 1.05),
        ]
        for (index, (point, alpha, scale)) in trail.enumerated() {
            let icon = Props.fileIcon(files.screenshot, side: 92)
            icon.position = point
            icon.alpha = alpha
            icon.setScale(scale)
            icon.zRotation = -0.12 * CGFloat(index)
            icon.zPosition = 10 + CGFloat(index)
            scene.addChild(icon)
        }
        let dropping = Props.fileIcon(files.taxes, side: 92)
        dropping.position = CGPoint(x: 990, y: 36 + basket.rimHeight - 4)
        dropping.zRotation = 0.15
        dropping.zPosition = Z.fileInside
        scene.addChild(dropping)

        let icon = Props.appIcon(side: 112)
        icon.position = CGPoint(x: 146, y: 478)
        scene.addChild(icon)
        let title = Props.label("Hoop", size: 132, weight: .heavy)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 84, y: 338)
        let tagline = Props.label("Throw files into your Mac’s Trash.", size: 38, weight: .semibold)
        tagline.horizontalAlignmentMode = .left
        tagline.position = CGPoint(x: 92, y: 238)
        let modes = Props.label("⌃⌥H to play  ·  Normal · Moving · Impossible", size: 24, color: NSColor(white: 1, alpha: 0.78))
        modes.horizontalAlignmentMode = .left
        modes.position = CGPoint(x: 92, y: 180)
        for node in [title, tagline, modes] { scene.addChild(node) }

        let renderer = FrameRenderer(scene: scene, width: Int(size.width) * 2, height: Int(size.height) * 2)
        renderer.render(at: 0)
        let rep = NSBitmapImageRep(cgImage: renderer.image())
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}
