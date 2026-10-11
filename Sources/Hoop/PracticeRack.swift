import SpriteKit

/// The Shot Clock's little rack of paper balls, standing on the floor. Take one off to throw it, and
/// a fresh one pops into its place once it's in or down. The node's origin is the middle of its base.
final class PracticeRack: SKNode {
    private enum Shape {
        static let slots = 3
        static let spacing: CGFloat = 60
        static let legHeight: CGFloat = 14
        static let tray = CGSize(width: 196, height: 9)
        /// Above the tray, under the files flying past.
        static let ballZ: CGFloat = 0.2
    }

    private var slots: [PaperBall?] = Array(repeating: nil, count: Shape.slots)

    /// The balls waiting on the rack.
    var balls: [PaperBall] { slots.compactMap { $0 } }

    override init() {
        super.init()
        zPosition = Z.backboard
        addStand()
        for slot in slots.indices { fill(slot) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The waiting ball under `point`, relative to the rack.
    func ball(at point: CGPoint) -> PaperBall? {
        balls.first { hypot($0.position.x - point.x, $0.position.y - point.y) < Throwable.radius + 6 }
    }

    /// Takes `ball` off the rack, leaving its slot empty until a refill. It stays where it is on screen.
    func take(_ ball: PaperBall) {
        guard let slot = slots.firstIndex(where: { $0 === ball }) else { return }
        slots[slot] = nil
        ball.zPosition = Z.file
        if let scene { ball.move(toParent: scene) }
    }

    /// A fresh ball pops into an empty slot.
    func refill() {
        guard let slot = slots.firstIndex(where: { $0 == nil }) else { return }
        fill(slot, popping: true)
    }

    private func fill(_ slot: Int, popping: Bool = false) {
        let ball = PaperBall()
        ball.position = CGPoint(
            x: (CGFloat(slot) - CGFloat(Shape.slots - 1) / 2) * Shape.spacing,
            y: Shape.legHeight + Shape.tray.height + Throwable.radius - 4
        )
        ball.zPosition = Shape.ballZ
        if popping {
            ball.setScale(0)
            let pop = SKAction.scale(to: 1.12, duration: 0.16)
            pop.timingMode = .easeOut
            ball.run(.sequence([.wait(forDuration: 0.25), pop, .scale(to: 1, duration: 0.1)]))
        }
        addChild(ball)
        slots[slot] = ball
    }

    /// A tray in the hoop's blue on two short legs, with a dip under each ball and a shadow on the floor.
    private func addStand() {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: Shape.tray.width + 10, height: 8))
        shadow.fillColor = NSColor(white: 0, alpha: 0.22)
        shadow.lineWidth = 0
        addChild(shadow)

        let legColor = Palette.rim.blended(withFraction: 0.3, of: .black) ?? Palette.rim
        for direction: CGFloat in [-1, 1] {
            let leg = SKShapeNode(rect: CGRect(x: direction * (Shape.tray.width / 2 - 22) - 3, y: 0, width: 6, height: Shape.legHeight + 2), cornerRadius: 2)
            leg.fillColor = legColor
            leg.lineWidth = 0
            leg.zPosition = 0.01
            addChild(leg)
        }

        let tray = SKShapeNode(rect: CGRect(x: -Shape.tray.width / 2, y: Shape.legHeight, width: Shape.tray.width, height: Shape.tray.height), cornerRadius: Shape.tray.height / 2)
        tray.fillColor = Palette.rim
        tray.strokeColor = NSColor(white: 1, alpha: 0.35)
        tray.lineWidth = 1
        tray.zPosition = 0.02
        addChild(tray)

        for slot in 0..<Shape.slots {
            let dip = SKShapeNode(ellipseOf: CGSize(width: 34, height: 5))
            dip.fillColor = NSColor(white: 0, alpha: 0.3)
            dip.lineWidth = 0
            dip.position = CGPoint(x: (CGFloat(slot) - CGFloat(Shape.slots - 1) / 2) * Shape.spacing, y: Shape.legHeight + Shape.tray.height - 1)
            dip.zPosition = 0.03
            addChild(dip)
        }
    }
}
