import SpriteKit

/// Something the player throws: a dragged file, or a Shot Clock paper ball. Either one flies as a
/// ball of `radius` and keeps track of its flight, for the scoring and the callouts.
class Throwable: SKNode {
    static let radius: CGFloat = 24

    /// False for a file popping back out after an undo, so it can't drop straight back in.
    var canScore = true
    /// Scoring or landed; no longer part of the game.
    var isLeaving = false
    var age: TimeInterval = 0
    var restingTime: TimeInterval = 0
    /// Where it was let go, in scene coordinates.
    var releasePoint = CGPoint.zero
    /// Hit a rim on the way.
    var hitRim = false
    /// Hit the Trash's backboard on the way.
    var hitBoard = false
    /// Where its centre was last frame, in scene coordinates, to tell when it drops through a hoop.
    var previousPosition: CGPoint?

    /// Let go and still moving or settling: not held, not on the rack, not yet in a goal or landed.
    var isInPlay: Bool { physicsBody != nil && !isLeaving }

    private var flame: FlameTrail?

    override init() {
        super.init()
        zPosition = Z.file
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Gives it its ball-like physics body: from now on it falls, and bounces off the rims, the
    /// backboard, the walls and other throws.
    func takeFlight() {
        let body = SKPhysicsBody(circleOfRadius: Self.radius)
        body.mass = 0.1
        body.allowsRotation = false
        body.restitution = 0.35
        body.friction = 0.5
        body.linearDamping = 0.1
        // Throws move fast and the can's lips and the backboard are thin edges; without this one can tunnel through.
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Physics.file
        body.collisionBitMask = Physics.wall | Physics.file | Physics.rim | Physics.board
        body.contactTestBitMask = Physics.wall | Physics.rim | Physics.board
        physicsBody = body
    }

    /// Follows its flight each frame (a file tilts, a paper ball spins).
    func updateLook() {}

    /// Trails flames behind it. Call once it's in the scene.
    func ignite() {
        guard flame == nil, let scene else { return }
        let flame = FlameTrail(leavingIn: scene)
        flame.zPosition = -1 // behind the icon
        addChild(flame)
        self.flame = flame
    }

    func extinguish() {
        flame?.burnOut()
        flame = nil
    }
}
