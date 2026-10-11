import SpriteKit

/// The folder hoop: a classic hoop with the folder's icon and name on its backboard. A file that
/// drops through the rim moves into the folder. The rim and net are split into back and front
/// halves, so a made file passes between them. The node's origin is the middle of the rim.
final class HoopNode: SKNode, Goal {
    let folder: URL

    private enum Shape {
        /// Radii of the rim, seen a little from above.
        static let rim = CGSize(width: 52, height: 11)
        static let netHeight: CGFloat = 64
        static let board = CGRect(x: -80, y: 26, width: 160, height: 104)
        static let iconSide: CGFloat = 52
    }

    private let backNet = SKShapeNode()
    private let frontNet = SKShapeNode()

    init(folder: URL) {
        self.folder = folder
        super.init()
        addBoard()

        let back = SKShapeNode(path: .ellipseArc(radii: Shape.rim, from: 0, to: .pi))
        back.strokeColor = Palette.rim.blended(withFraction: 0.3, of: .black) ?? Palette.rim
        back.zPosition = Z.basketBack + 0.1
        let front = SKShapeNode(path: .ellipseArc(radii: Shape.rim, from: .pi, to: 2 * .pi))
        front.strokeColor = Palette.rim
        front.zPosition = Z.basketFront + 0.1
        for (rim, width) in [(back, CGFloat(5)), (front, 6)] {
            rim.lineWidth = width
            rim.lineCap = .round
            addChild(rim)
        }

        backNet.strokeColor = NSColor(white: 1, alpha: 0.5)
        backNet.lineWidth = 1.5
        backNet.zPosition = Z.basketBack
        frontNet.strokeColor = NSColor(white: 1, alpha: 0.95)
        frontNet.lineWidth = 2
        frontNet.zPosition = Z.basketFront
        for net in [backNet, frontNet] {
            net.lineCap = .round
            addChild(net)
        }
        drawNet()

        // Only the rim's ends are solid: a file can clip one and bounce out, or drop through between them.
        for direction: CGFloat in [-1, 1] {
            let end = SKPhysicsBody(circleOfRadius: 4, center: CGPoint(x: direction * Shape.rim.width, y: 0))
            end.isDynamic = false
            end.restitution = 0.5
            end.categoryBitMask = Physics.rim
            let holder = SKNode()
            holder.physicsBody = end
            addChild(holder)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Goal

    var target: Target { .folder(folder) }
    let opening = CGPoint.zero
    let hasRim = true

    /// The backboard on top down to the bottom of the net.
    var extent: CGRect {
        CGRect(x: Shape.board.minX, y: -Shape.netHeight - 4, width: Shape.board.width, height: Shape.board.maxY + Shape.netHeight + 4)
    }

    /// In when the centre crosses the rim's line between its ends on the way down, so only a file
    /// coming from above counts.
    func takesIn(from start: CGPoint, to end: CGPoint) -> Bool {
        guard start.y >= 0, end.y < 0 else { return false }
        let x = start.x + (end.x - start.x) * start.y / (start.y - end.y)
        return abs(x) < Shape.rim.width
    }

    /// Let go inside the rim or the top of the net.
    func isDunk(at point: CGPoint) -> Bool {
        abs(point.x) < Shape.rim.width && point.y > -Shape.netHeight * 0.6 && point.y < Throwable.radius
    }

    func covers(_ point: CGPoint) -> Bool {
        let hoop = CGRect(x: -Shape.rim.width - 6, y: -Shape.netHeight, width: 2 * (Shape.rim.width + 6), height: Shape.netHeight + Shape.board.minY)
        return Shape.board.insetBy(dx: -4, dy: -4).contains(point) || hoop.contains(point)
    }

    /// It drops through the net, which swishes.
    func swallow(_ thrown: Throwable) {
        let drop = SKAction.move(to: CGPoint(x: position.x, y: position.y - Shape.netHeight * 0.8), duration: 0.3)
        drop.timingMode = .easeIn
        let fade = SKAction.sequence([.wait(forDuration: 0.16), .fadeOut(withDuration: 0.14)])
        thrown.run(.group([drop, .scale(to: 0.6, duration: 0.3), fade])) {
            thrown.removeFromParent()
        }
        swish()
    }

    // MARK: Drawing

    /// A white board, like the app icon's, with the folder's Finder icon and name, on a bracket over the rim.
    private func addBoard() {
        let board = SKShapeNode(rect: Shape.board, cornerRadius: 12)
        board.fillColor = NSColor(white: 1, alpha: 0.92)
        board.strokeColor = NSColor(hex: 0xA1A7B3)
        board.lineWidth = 3
        board.zPosition = Z.backboard
        addChild(board)

        let bracket = CGMutablePath()
        bracket.addLines(between: [
            CGPoint(x: -20, y: Shape.rim.height - 3), CGPoint(x: 20, y: Shape.rim.height - 3),
            CGPoint(x: 13, y: Shape.board.minY + 2), CGPoint(x: -13, y: Shape.board.minY + 2),
        ])
        bracket.closeSubpath()
        let mount = SKShapeNode(path: bracket)
        mount.fillColor = Palette.rim
        mount.lineWidth = 0
        mount.zPosition = Z.backboard + 0.01
        addChild(mount)

        var rect = CGRect(x: 0, y: 0, width: Shape.iconSide * 2, height: Shape.iconSide * 2)
        if let image = NSWorkspace.shared.icon(forFile: folder.path(percentEncoded: false)).cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            let icon = SKSpriteNode(texture: SKTexture(cgImage: image), size: CGSize(width: Shape.iconSide, height: Shape.iconSide))
            icon.position = CGPoint(x: 0, y: Shape.board.minY + Shape.board.height * 0.62)
            icon.zPosition = Z.backboard + 0.01
            addChild(icon)
        }

        let name = SKLabelNode()
        name.attributedText = .label(folder.displayName.middleTruncated(to: 20), size: 13, weight: .semibold, color: NSColor(white: 0.2, alpha: 1))
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: 0, y: Shape.board.minY + 20)
        name.zPosition = Z.backboard + 0.01
        addChild(name)
    }

    private func drawNet(swing: CGFloat = 0) {
        let net = NetGeometry.segments(rx: Shape.rim.width, ry: Shape.rim.height, height: Shape.netHeight, swing: swing)
        backNet.path = .lines(net.back)
        frontNet.path = .lines(net.front)
    }

    /// The net stretches as the file goes through, recoils and settles. It runs on the net, so moving
    /// or regrowing the hoop doesn't cut it short.
    private func swish() {
        let duration: CGFloat = 0.7
        let swing = SKAction.customAction(withDuration: duration) { [weak self] _, elapsed in
            let progress = elapsed / duration
            self?.drawNet(swing: 1.4 * sin(2.5 * .pi * progress) * exp(-3 * progress))
        }
        frontNet.run(.sequence([swing, .run { [weak self] in self?.drawNet() }]), withKey: "swish")
    }
}
