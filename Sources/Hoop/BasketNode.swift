import SpriteKit

/// The Trash, grown out of its Dock tile, used as the basket. The artwork is split along the front
/// lip of its opening: the back part draws behind a file dropping in, the front part over it.
/// The node's origin is the bottom of the can, so scaling it grows the can upwards.
final class BasketNode: SKNode, Goal {
    let side: CGFloat
    /// A solid can only lets files in through its opening. A Dock-sized one is smaller than a
    /// thrown file, so instead it catches any file that touches it.
    let isSolid: Bool
    /// Height of the opening above the bottom of the can.
    var rimHeight: CGFloat { y(Art.openingCenter) }
    /// Half the width of the can at its lip.
    var outerHalfWidth: CGFloat { side * Art.lipHalfWidth }
    /// Half the width of the can, out to the far edge of its backboard when it has one.
    var reach: CGFloat { backboard.map { outerHalfWidth + side * Art.boardGap + $0.size.width } ?? outerHalfWidth }

    var isFull = false {
        didSet { if isFull != oldValue { applyTexture() } }
    }

    /// A glass backboard rising from one end of the lip, to bank shots off. Only for a solid can.
    var hasBackboard: Bool {
        get { backboard != nil }
        set {
            guard newValue != hasBackboard else { return }
            backboard?.removeFromParent()
            backboard = newValue ? Backboard(size: CGSize(width: side * Art.boardWidth, height: side * Art.boardHeight)) : nil
            if let backboard { addChild(backboard) }
            placeBackboard()
        }
    }

    /// Which side of the can the backboard stands on.
    var isBackboardOnRight = true {
        didSet { if isBackboardOnRight != oldValue { placeBackboard() } }
    }

    // MARK: Goal

    let target = Target.trash
    var opening: CGPoint { CGPoint(x: 0, y: rimHeight) }
    /// The Dock-sized Trash has no rim to touch.
    var hasRim: Bool { isSolid }

    /// The can, with room for its backboard on either side.
    var extent: CGRect {
        let top = backboard.map { $0.position.y + $0.size.height / 2 } ?? side
        return CGRect(x: -reach - 10, y: 0, width: 2 * (reach + 10), height: max(side, top))
    }

    /// Landmarks in the system Trash artwork, as fractions of the icon measured from its top.
    private enum Art {
        static let openingCenter: CGFloat = 0.175
        static let openingDepth: CGFloat = 0.05 // half-height of the opening's inner ellipse
        static let lipHalfWidth: CGFloat = 0.36
        static let lipSides: CGFloat = 0.18
        static let bottom: CGFloat = 0.9
        static let bottomHalfWidth: CGFloat = 0.26
        /// The backboard's size, and its gap to the lip.
        static let boardWidth: CGFloat = 0.16
        static let boardHeight: CGFloat = 0.85
        static let boardGap: CGFloat = 0.015
    }

    private let back = SKSpriteNode()
    private let front = SKSpriteNode()
    private var backboard: Backboard?
    private var catchMargin: CGFloat { isSolid ? 0 : Throwable.radius * 0.8 }

    /// Where the bottom of the can sits for the Trash in a Dock tile: the icon is the tile's top
    /// square, and its artwork ends a little above the icon's bottom edge.
    static func base(onDockTile tile: CGRect) -> CGPoint {
        let icon = min(tile.width, tile.height)
        return CGPoint(x: tile.midX, y: tile.maxY - icon * Art.bottom)
    }

    init(side: CGFloat, isFull: Bool, isSolid: Bool = true) {
        self.side = side
        self.isFull = isFull
        self.isSolid = isSolid
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
        guard isSolid else { return }

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

    /// Whether a point, relative to the bottom of the can, is inside it (below the opening, between
    /// the sides), or for a Dock-sized can, on or right next to it.
    func isInside(_ point: CGPoint) -> Bool {
        guard point.y > -catchMargin, point.y < rimHeight + catchMargin else { return false }
        let progress = max(0, min(1, point.y / rimHeight))
        let halfWidth = side * (Art.bottomHalfWidth + (Art.lipHalfWidth - Art.bottomHalfWidth) * progress)
        return abs(point.x) < halfWidth + catchMargin
    }

    /// Whether a point, relative to the bottom of the can, is on the can (for grabbing it).
    func covers(_ point: CGPoint) -> Bool {
        abs(point.x) < outerHalfWidth + 6 && point.y > -6 && point.y < rimHeight + side * 0.08
    }

    /// The can's sides are solid, so a file whose centre is inside it came in through the top.
    func takesIn(from _: CGPoint, to end: CGPoint) -> Bool {
        isInside(end)
    }

    func isDunk(at point: CGPoint) -> Bool {
        isInside(point)
    }

    /// It shrinks down into the can, which gives a little squash, and a file shows it's full.
    /// A paper ball leaves the real Trash looking as it is.
    func swallow(_ thrown: Throwable) {
        let target = CGPoint(x: position.x, y: position.y + rimHeight * 0.45)
        let drop = SKAction.move(to: target, duration: 0.26)
        drop.timingMode = .easeIn
        let fade = SKAction.sequence([.wait(forDuration: 0.14), .fadeOut(withDuration: 0.12)])
        thrown.run(.group([drop, .scale(to: isSolid ? 0.55 : 0.3, duration: 0.26), fade])) { [weak self] in
            thrown.removeFromParent()
            self?.bump()
            if thrown is FileNode { self?.isFull = true }
        }
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

    /// Stands the backboard just outside the lip on its side, rising from the lip's end.
    private func placeBackboard() {
        guard let backboard else { return }
        let x = outerHalfWidth + side * Art.boardGap + backboard.size.width / 2
        backboard.position = CGPoint(x: isBackboardOnRight ? x : -x, y: y(Art.lipSides) + backboard.size.height / 2)
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
