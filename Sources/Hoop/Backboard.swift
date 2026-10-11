import SpriteKit

/// A pane of glass standing beside the Trash. Files bounce off it, and one that goes in after
/// touching it is a bank shot. Its origin is its centre.
final class Backboard: SKNode {
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        super.init()
        zPosition = Z.backboard
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

        let pane = SKShapeNode(rect: rect, cornerRadius: 3)
        pane.fillColor = NSColor(white: 1, alpha: 0.12)
        pane.strokeColor = NSColor(white: 1, alpha: 0.6)
        pane.lineWidth = 2
        addChild(pane)

        // The shooter's square, low on the board like on a real one.
        let side = size.width * 0.56
        let square = SKShapeNode(rect: CGRect(x: -side / 2, y: rect.minY + size.height * 0.1, width: side, height: side))
        square.fillColor = .clear
        square.strokeColor = NSColor(white: 1, alpha: 0.3)
        square.lineWidth = 1.5
        square.zPosition = 0.01
        addChild(square)

        let body = SKPhysicsBody(edgeLoopFrom: rect)
        body.restitution = 0.6
        body.friction = 0.2
        body.categoryBitMask = Physics.board
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
