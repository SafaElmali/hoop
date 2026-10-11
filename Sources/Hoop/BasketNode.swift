import SpriteKit

/// The Trash, grown out of its Dock tile, used as the basket. The artwork is split along the front
/// lip of its opening: the back part draws behind a file dropping in, the front part over it.
/// The node's origin is the bottom of the can, so scaling it grows the can upwards.
final class BasketNode: SKNode {
    let side: CGFloat
    /// Height of the opening above the bottom of the can.
    var rimHeight: CGFloat { y(Art.openingCenter) }
    /// Half the width of the can at its lip.
    var outerHalfWidth: CGFloat { side * Art.lipHalfWidth }

    var isFull = false {
        didSet { if isFull != oldValue { applyTexture() } }
    }

    /// Landmarks in the system Trash artwork, as fractions of the icon measured from its top.
    private enum Art {
        static let openingCenter: CGFloat = 0.175
        static let openingDepth: CGFloat = 0.05 // half-height of the opening's inner ellipse
        static let lipHalfWidth: CGFloat = 0.36
        static let lipSides: CGFloat = 0.18
        static let bottom: CGFloat = 0.9
        static let bottomHalfWidth: CGFloat = 0.26
    }

    private let back = SKSpriteNode()
    private let front = SKSpriteNode()

    init(side: CGFloat, isFull: Bool) {
        self.side = side
        self.isFull = isFull
        super.init()

        let artCenter = CGPoint(x: 0, y: side * (Art.bottom - 0.5))
        for (sprite, isFront) in [(back, false), (front, true)] {
            sprite.size = CGSize(width: side, height: side)
            sprite.position = artCenter
            let crop = SKCropNode()
            crop.maskNode = mask(front: isFront, artCenter: artCenter)
            crop.zPosition = isFront ? Z.basketFront : Z.basketBack
            crop.addChild(sprite)
            addChild(crop)
        }
        applyTexture()

        // The lip's ends, sides and bottom are solid (it can be dragged off the floor), so the
        // opening at the top is the only way in.
        let foot = CGPoint(x: side * Art.bottomHalfWidth, y: y(Art.bottom - 0.01))
        var bodies = [SKPhysicsBody(edgeFrom: CGPoint(x: -foot.x, y: foot.y), to: foot)]
        for direction: CGFloat in [-1, 1] {
            let lip = CGPoint(x: direction * outerHalfWidth, y: y(Art.lipSides))
            bodies += [SKPhysicsBody(circleOfRadius: 4, center: lip), SKPhysicsBody(edgeFrom: lip, to: CGPoint(x: direction * foot.x, y: foot.y))]
        }
        for body in bodies {
            body.isDynamic = false
            body.restitution = 0.5
            body.categoryBitMask = Physics.rim
            let holder = SKNode()
            holder.physicsBody = body
            addChild(holder)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Whether a point, relative to the bottom of the can, is inside it (below the opening, between the sides).
    func isInside(_ point: CGPoint) -> Bool {
        guard point.y > 0, point.y < rimHeight else { return false }
        let progress = point.y / rimHeight
        let halfWidth = side * (Art.bottomHalfWidth + (Art.lipHalfWidth - Art.bottomHalfWidth) * progress)
        return abs(point.x) < halfWidth
    }

    /// Whether a point, relative to the bottom of the can, is on the can (for grabbing it).
    func covers(_ point: CGPoint) -> Bool {
        abs(point.x) < outerHalfWidth + 6 && point.y > -6 && point.y < rimHeight + side * 0.08
    }

    /// A little squash when something lands inside.
    func bump() {
        let squash = SKAction.scaleX(to: 1.07, y: 0.93, duration: 0.07)
        let settle = SKAction.scale(to: 1, duration: 0.25)
        settle.timingMode = .easeOut
        run(.sequence([squash, settle]))
    }

    /// Height above the bottom of the can for a point `fraction` down from the top of the artwork.
    private func y(_ fraction: CGFloat) -> CGFloat {
        side * (Art.bottom - fraction)
    }

    private func applyTexture() {
        guard let image = NSImage(named: isFull ? NSImage.trashFullName : NSImage.trashEmptyName) else { return }
        var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        let texture = SKTexture(cgImage: cgImage)
        back.texture = texture
        front.texture = texture
    }

    /// Everything below (front) or above (back) the near edge of the opening.
    private func mask(front: Bool, artCenter: CGPoint) -> SKShapeNode {
        let half = side / 2 + 2
        let rimY = rimHeight
        let radiusX = side * (Art.lipHalfWidth + 0.02)
        let radiusY = side * Art.openingDepth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -half, y: rimY))
        for step in 0...32 {
            let angle = CGFloat.pi + .pi * CGFloat(step) / 32
            path.addLine(to: CGPoint(x: radiusX * cos(angle), y: rimY + radiusY * sin(angle)))
        }
        path.addLine(to: CGPoint(x: half, y: rimY))
        let edge = artCenter.y + (front ? -half : half)
        path.addLine(to: CGPoint(x: half, y: edge))
        path.addLine(to: CGPoint(x: -half, y: edge))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = .white
        shape.lineWidth = 0
        return shape
    }
}
