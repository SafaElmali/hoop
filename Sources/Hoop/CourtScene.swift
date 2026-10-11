import SpriteKit

enum Physics {
    static let file: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let rim: UInt32 = 1 << 2
    /// The Trash's glass backboard.
    static let board: UInt32 = 1 << 3
}

/// Draw order. A scoring file slots between the back and front of a goal so it drops *into* it.
enum Z {
    /// Behind a goal: the Trash's glass, the folder hoop's board.
    static let backboard: CGFloat = 0.5
    static let basketBack: CGFloat = 1
    static let fileInside: CGFloat = 2
    static let basketFront: CGFloat = 3
    static let file: CGFloat = 10
}

/// How the Trash behaves in shoot mode. The folder hoop always stays put.
enum Mode: String, CaseIterable {
    /// Stays put; drag it wherever you like.
    case normal
    /// Glides back and forth along the bottom of the screen.
    case moving
    /// Darts out of the way just before a file would drop in.
    case impossible

    var title: String {
        switch self {
        case .normal: "Normal"
        case .moving: "Moving"
        case .impossible: "Impossible"
        }
    }
}

/// How big the Trash grows in shoot mode.
enum BasketSize: String, CaseIterable {
    case small, medium, large, huge
    /// The real Trash in the Dock: its size, at its spot.
    case dock

    var title: String { self == .dock ? "Dock Size" : rawValue.capitalized }

    /// Grown sizes leave room for a thrown file in the opening; the Dock's Trash is too small for that.
    var isSolid: Bool { self != .dock }

    /// Side of the Trash artwork, in points.
    func side(dockTile: CGRect?) -> CGFloat {
        switch self {
        case .small: 110
        case .medium: 150
        case .large: 210
        case .huge: 300
        case .dock: dockTile.map { min($0.width, $0.height) } ?? 64
        }
    }
}

/// How a file went in, for the callout, and where it goes.
struct MakeInfo {
    /// The Trash, or the folder hoop's folder.
    let target: Target
    /// From where the file was let go to the opening, in points.
    let distance: CGFloat
    /// Didn't touch a rim or the backboard on the way in.
    let isClean: Bool
    /// Dropped straight in.
    let isDunk: Bool
    /// Went in after touching the Trash's backboard.
    let isBank: Bool
}

/// The whole screen is the court, and the Trash (plus the folder hoop, when it's up) are the goals.
/// Thrown files fly with the momentum of the drag; into a goal they go where it sends them,
/// otherwise they stay where they land.
final class CourtScene: SKScene, SKPhysicsContactDelegate {
    /// A file went in: trash it, or move it into the folder hoop's folder, as `make.target` says.
    var onScore: ((_ url: URL, _ make: MakeInfo) -> Void)?
    /// A file came to rest outside the goals at this point. False for a file popping out after an undo.
    var onLand: ((_ url: URL, _ point: CGPoint, _ wasThrown: Bool) -> Void)?
    /// The player dragged the Trash somewhere new (the bottom of the can, in scene coordinates).
    var onBasketMoved: ((CGPoint) -> Void)?
    /// The player dragged the folder hoop somewhere new (the middle of its rim, in scene coordinates).
    var onHoopMoved: ((CGPoint) -> Void)?
    var mode = Mode.normal {
        didSet { if mode != oldValue { modeChanged() } }
    }
    var basketSize = BasketSize.medium {
        didSet { if basketSize != oldValue { resizeBasket() } }
    }
    /// The grown Trash has a glass backboard to bank shots off, on its side away from the middle of the screen.
    var hasBackboard = false {
        didSet { if let basket { basket.hasBackboard = hasBackboard && basket.isSolid } }
    }
    /// On a streak: files thrown from now on trail flames.
    var isOnFire = false

    var fileNodes: [FileNode] { children.compactMap { $0 as? FileNode } }

    private enum Tuning {
        static let maxThrowSpeed: CGFloat = 3200
        static let restBeforeLanding: TimeInterval = 0.5
        static let maxFlightTime: TimeInterval = 6
        static let movingPeriod: CGFloat = 8
        /// Impossible mode dodges a file this many seconds before it would drop in.
        static let dodgeLookahead: CGFloat = 0.3
        /// SpriteKit simulates 150 points per metre.
        static let pointsPerMetre: CGFloat = 150
    }

    private enum ActionKey {
        static let dash = "dash"
        static let home = "home"
    }

    private let sounds: SoundEffects
    private var basket: BasketNode?
    private var hoop: HoopNode?
    /// Where the Trash rests (the bottom of the can) when it isn't moving or dodging.
    private var home = CGPoint.zero
    /// The Trash tile in the Dock while the basket sits on it; dropping a file there is a dunk.
    private var dockTile: CGRect?
    /// The goal being dragged, and the pointer's offset to its position.
    private var grab: (goal: Goal, offset: CGVector)?
    private var movingPhase: CGFloat = 0
    private var now: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    /// What files can go into, the Trash first.
    private var goals: [Goal] {
        let goals: [Goal?] = [basket, hoop]
        return goals.compactMap { $0 }
    }

    init(sounds: SoundEffects) {
        self.sounds = sounds
        super.init(size: CGSize(width: 100, height: 100))
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -11)
        physicsWorld.contactDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Floor at the bottom of the screen, walls at the sides, and a ceiling far above
    /// so high throws leave the screen and fall back in.
    override func didChangeSize(_ oldSize: CGSize) {
        let walls = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: size.width, height: size.height + 400))
        walls.categoryBitMask = Physics.wall
        walls.friction = 0.6
        walls.restitution = 0.3
        physicsBody = walls
    }

    // MARK: Public

    /// Places the Trash with the bottom of the can at `home`; from the Dock it grows out of its tile.
    func mountBasket(home: CGPoint, dockTile: CGRect?, animated: Bool) {
        self.home = home
        self.dockTile = dockTile
        let basket = currentBasket()
        if let isFull = Self.trashHasItems() { basket.isFull = isFull }
        basket.removeAllActions()
        basket.position = home
        basket.setScale(1)
        syncMovingPhase()
        guard animated else { return }
        grow(basket, from: dockTile.map { $0.height / basket.side } ?? 0.3)
    }

    /// Puts up the folder hoop for `folder` with the middle of its rim at `rimCenter`, or takes it
    /// down for nil. Unlike the Trash, it stays put in every mode.
    func mountHoop(folder: URL?, rimCenter: CGPoint, animated: Bool) {
        guard let folder else {
            hoop?.removeFromParent()
            hoop = nil
            return
        }
        let hoop = currentHoop(for: folder)
        hoop.removeAllActions()
        hoop.position = rimCenter
        hoop.setScale(1)
        if animated { grow(hoop, from: 0.3) }
    }

    /// Whether a goal that can be dragged is under `point`. The Dock-sized Trash stays in the Dock.
    func isOverGoal(_ point: CGPoint) -> Bool {
        draggableGoal(at: point) != nil
    }

    /// Launches dropped files from `point` with the drag's velocity. Dropping right on a goal is a dunk.
    func throwFiles(_ urls: [URL], at point: CGPoint, velocity: CGVector) {
        var dunkedInto = goal(droppedOnAt: point)
        if mode == .impossible, let basket, dunkedInto === basket {
            dodge(awayFrom: point.x, basket: basket, instantly: true)
            dunkedInto = nil
        }
        let speed = hypot(velocity.dx, velocity.dy)
        let scale = speed > Tuning.maxThrowSpeed ? Tuning.maxThrowSpeed / speed : 1
        if dunkedInto == nil {
            let loudness = Float(min(1, max(0, (speed - 500) / 2200)))
            if loudness > 0.05 { sounds.play(.whoosh, volume: loudness * 0.8) }
        }
        for (index, url) in urls.prefix(12).enumerated() {
            let file = FileNode(url: url)
            let spread = CGFloat(index) * 12
            file.position = CGPoint(
                x: min(max(point.x + spread, FileNode.radius), size.width - FileNode.radius),
                y: max(point.y + spread, FileNode.radius)
            )
            file.releasePoint = file.position
            file.previousPosition = file.position
            addChild(file)
            if let dunkedInto {
                score(file, in: dunkedInto, isDunk: true)
            } else {
                let damping = 1 - CGFloat(index) * 0.04
                file.physicsBody?.velocity = CGVector(dx: velocity.dx * scale * damping, dy: velocity.dy * scale * damping)
                if isOnFire { file.ignite() }
            }
        }
    }

    /// After an undo: the file pops back out of where it went (the Trash, or the folder hoop while
    /// it's up for that folder), towards the middle of the screen.
    func respawn(_ url: URL, from target: Target = .trash) {
        guard let goal = goals.first(where: { $0.target == target }) ?? basket else { return }
        let file = FileNode(url: url)
        file.canScore = false
        let opening = opening(of: goal)
        file.position = CGPoint(x: opening.x, y: opening.y + FileNode.radius + 6)
        file.alpha = 0
        addChild(file)
        let direction: CGFloat = goal.position.x > size.width / 2 ? -1 : 1
        file.physicsBody?.velocity = CGVector(dx: direction * .random(in: 260...360), dy: 700)
        file.run(.fadeIn(withDuration: 0.12))
        if let basket, let isFull = Self.trashHasItems() { basket.isFull = isFull }
    }

    func clear() {
        for node in children where node is FileNode || node is FlameTrail { node.removeFromParent() }
        grab = nil
    }

    // MARK: Dragging the goals

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard let goal = draggableGoal(at: point) else { return }
        goal.removeAction(forKey: ActionKey.dash)
        goal.removeAction(forKey: ActionKey.home)
        grab = (goal, CGVector(dx: goal.position.x - point.x, dy: goal.position.y - point.y))
        goal.run(.scale(to: 1.06, duration: 0.1))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab else { return }
        let point = event.location(in: self)
        grab.goal.position = clamped(CGPoint(x: point.x + grab.offset.dx, y: point.y + grab.offset.dy), for: grab.goal)
    }

    override func mouseUp(with event: NSEvent) {
        guard let goal = grab?.goal else { return }
        grab = nil
        goal.run(.scale(to: 1, duration: 0.15))
        if goal === hoop {
            onHoopMoved?(goal.position)
        } else {
            home = goal.position
            dockTile = nil
            syncMovingPhase()
            onBasketMoved?(home)
        }
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        elapsed = now > 0 ? min(currentTime - now, 0.1) : 0
        now = currentTime
        if mode == .moving, let basket, grab?.goal !== basket {
            movingPhase += CGFloat(elapsed) * 2 * .pi / Tuning.movingPeriod
            basket.position = CGPoint(x: trackCenter + trackAmplitude * sin(movingPhase), y: home.y)
        }
    }

    /// Wherever the Trash went (gliding, dodging, dragged or resized), its backboard stands on the side
    /// away from the middle of the screen.
    override func didEvaluateActions() {
        guard let basket else { return }
        basket.isBackboardOnRight = basket.position.x > size.width / 2
    }

    override func didSimulatePhysics() {
        if mode == .impossible, let basket, grab?.goal !== basket, basket.action(forKey: ActionKey.dash) == nil,
           let incoming = incomingDrop(into: basket) {
            dodge(awayFrom: incoming, basket: basket)
        }
        for file in fileNodes where !file.isLeaving {
            let velocity = file.physicsBody?.velocity ?? .zero
            if file.canScore, let goal = goal(takingIn: file) {
                score(file, in: goal)
                continue
            }
            file.previousPosition = file.position
            file.age += elapsed
            file.restingTime = hypot(velocity.dx, velocity.dy) < 40 ? file.restingTime + elapsed : 0
            if file.restingTime > Tuning.restBeforeLanding || file.age > Tuning.maxFlightTime {
                land(file)
            }
        }
        fileNodes.forEach { $0.updateLook() }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        let impulse = Float(contact.collisionImpulse)
        let file = contact.bodyA.node as? FileNode ?? contact.bodyB.node as? FileNode
        if categories & Physics.rim != 0, impulse > 0.05 {
            sounds.play(.clank, volume: min(1, impulse / 0.8))
            file?.hitRim = true
        } else if categories & Physics.board != 0, impulse > 0.05 {
            sounds.play(.thud, volume: min(0.9, impulse))
            file?.hitBoard = true
        } else if categories & Physics.wall != 0, impulse > 0.15 {
            sounds.play(.thud, volume: min(0.9, impulse))
        }
    }

    // MARK: Scoring

    private func score(_ file: FileNode, in goal: Goal, isDunk: Bool = false) {
        file.isLeaving = true
        file.physicsBody = nil
        file.zPosition = Z.fileInside
        file.extinguish()
        let opening = opening(of: goal)
        let make = MakeInfo(
            target: goal.target,
            distance: hypot(opening.x - file.releasePoint.x, opening.y - file.releasePoint.y),
            isClean: goal.hasRim && !file.hitRim && !file.hitBoard,
            isDunk: isDunk,
            isBank: file.hitBoard
        )
        // Trash or move it right away, so Finder's trash sound lands with the file.
        onScore?(file.url, make)
        goal.swallow(file)
    }

    /// A miss: the file stays where it came to rest (for a desktop file, its real icon moves there).
    private func land(_ file: FileNode) {
        file.isLeaving = true
        file.physicsBody = nil
        file.extinguish()
        onLand?(file.url, file.position, file.canScore)
        file.run(.sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// The goal `file` went into this frame, if any.
    private func goal(takingIn file: FileNode) -> Goal? {
        let start = file.previousPosition ?? file.position
        return goals.first { $0.takesIn(from: offset(of: start, from: $0), to: offset(of: file.position, from: $0)) }
    }

    /// The goal a file let go at `point` drops straight into: onto a goal, or onto the Trash tile in the Dock.
    private func goal(droppedOnAt point: CGPoint) -> Goal? {
        if let basket, dockTile?.insetBy(dx: -6, dy: -6).contains(point) == true { return basket }
        return goals.first { $0.isDunk(at: offset(of: point, from: $0)) }
    }

    // MARK: Moving and impossible modes

    private var trackCenter: CGFloat { size.width / 2 }
    private var trackAmplitude: CGFloat { max(0, size.width / 2 - (basket?.reach ?? 60) - 40) }

    private func modeChanged() {
        guard let basket else { return }
        basket.removeAction(forKey: ActionKey.dash)
        basket.removeAction(forKey: ActionKey.home)
        if mode == .moving {
            syncMovingPhase()
        } else {
            glideHome(after: 0)
        }
    }

    /// Continues the back-and-forth from wherever the Trash is now.
    private func syncMovingPhase() {
        guard let basket, trackAmplitude > 0 else { return }
        movingPhase = asin(max(-1, min(1, (basket.position.x - trackCenter) / trackAmplitude)))
    }

    /// Where a file will cross the height of the opening, if it's about to drop into the Trash.
    private func incomingDrop(into basket: BasketNode) -> CGFloat? {
        let halfGravity = 0.5 * physicsWorld.gravity.dy * Tuning.pointsPerMetre
        let rimY = basket.position.y + basket.rimHeight
        for file in fileNodes where file.canScore && !file.isLeaving {
            guard let velocity = file.physicsBody?.velocity else { continue }
            // Solve y(t) = rimY for the falling crossing: halfGravity·t² + vy·t + (y - rimY) = 0.
            let discriminant = velocity.dy * velocity.dy - 4 * halfGravity * (file.position.y - rimY)
            guard discriminant >= 0 else { continue }
            let time = (-velocity.dy - discriminant.squareRoot()) / (2 * halfGravity)
            guard time >= 0, time < Tuning.dodgeLookahead else { continue }
            let x = file.position.x + velocity.dx * time
            if abs(x - basket.position.x) < basket.outerHalfWidth + FileNode.radius * 0.6 { return x }
        }
        return nil
    }

    /// Darts sideways, away from `x`, then drifts back home a moment later.
    private func dodge(awayFrom x: CGFloat, basket: BasketNode, instantly: Bool = false) {
        let margin = basket.reach + 20
        let distance = basket.outerHalfWidth * 2.4 + .random(in: 0...90)
        let allowed = margin...max(margin, size.width - margin)
        var direction: CGFloat = x > basket.position.x ? -1 : 1
        if !allowed.contains(basket.position.x + direction * distance) { direction = -direction }
        let targetX = min(max(basket.position.x + direction * distance, allowed.lowerBound), allowed.upperBound)
        let target = CGPoint(x: targetX, y: basket.position.y)

        basket.removeAction(forKey: ActionKey.home)
        if instantly {
            basket.position = target
        } else {
            let dash = SKAction.move(to: target, duration: 0.11)
            dash.timingMode = .easeOut
            basket.run(dash, withKey: ActionKey.dash)
        }
        sounds.play(.dodge, volume: 0.9)
        glideHome(after: 1.3)
    }

    private func glideHome(after delay: TimeInterval) {
        guard let basket else { return }
        let glide = SKAction.move(to: home, duration: 0.5)
        glide.timingMode = .easeInEaseOut
        basket.run(.sequence([.wait(forDuration: delay), glide]), withKey: ActionKey.home)
    }

    // MARK: Helpers

    /// The Trash at the current size, made or remade as needed.
    private func currentBasket() -> BasketNode {
        if let basket, basket.side == basketSize.side(dockTile: dockTile), basket.isSolid == basketSize.isSolid {
            return basket
        }
        let old = basket
        let basket = BasketNode(side: basketSize.side(dockTile: dockTile), isFull: old?.isFull ?? Self.trashHasItems() ?? false, isSolid: basketSize.isSolid)
        basket.position = old?.position ?? home
        basket.hasBackboard = hasBackboard && basket.isSolid
        old?.removeFromParent()
        addChild(basket)
        self.basket = basket
        return basket
    }

    /// The folder hoop for `folder`, made or remade as needed.
    private func currentHoop(for folder: URL) -> HoopNode {
        if let hoop, hoop.folder == folder { return hoop }
        hoop?.removeFromParent()
        let hoop = HoopNode(folder: folder)
        addChild(hoop)
        self.hoop = hoop
        return hoop
    }

    /// Swaps in a Trash of the new size where the old one stood, with a little pop.
    private func resizeBasket() {
        guard let old = basket else { return }
        let resized = currentBasket()
        guard resized !== old else { return }
        resized.setScale(old.side / resized.side)
        let pop = SKAction.scale(to: 1, duration: 0.25)
        pop.timingMode = .easeOut
        resized.run(pop)
        if mode == .moving { syncMovingPhase() } else if resized.position != home { glideHome(after: 0) }
    }

    /// Grows `node` to full size from `scale`, overshooting a little before it settles.
    private func grow(_ node: SKNode, from scale: CGFloat) {
        node.setScale(scale)
        let grow = SKAction.scale(to: 1, duration: 0.4)
        grow.timingFunction = { t in Float(1 - pow(1 - Double(t), 3) * cos(Double(t) * 5)) } // overshoot, settle
        node.run(grow)
    }

    private func draggableGoal(at point: CGPoint) -> Goal? {
        goals.first { ($0 !== basket || basketSize != .dock) && $0.covers(offset(of: point, from: $0)) }
    }

    /// The middle of a goal's opening, in scene coordinates.
    private func opening(of goal: Goal) -> CGPoint {
        CGPoint(x: goal.position.x + goal.opening.x, y: goal.position.y + goal.opening.y)
    }

    private func offset(of point: CGPoint, from goal: Goal) -> CGPoint {
        CGPoint(x: point.x - goal.position.x, y: point.y - goal.position.y)
    }

    /// Keeps a dragged goal on screen.
    private func clamped(_ point: CGPoint, for goal: Goal) -> CGPoint {
        let extent = goal.extent
        return CGPoint(
            x: min(max(point.x, -extent.minX), size.width - extent.maxX),
            y: min(max(point.y, -extent.minY), size.height - extent.maxY)
        )
    }

    /// Listing ~/.Trash needs Full Disk Access; nil when it can't be read.
    private static func trashHasItems() -> Bool? {
        guard let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first,
              let items = try? FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false))
        else { return nil }
        return items.contains { $0 != ".DS_Store" }
    }
}
