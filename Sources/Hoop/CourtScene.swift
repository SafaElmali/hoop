import SpriteKit

enum Physics {
    static let file: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let rim: UInt32 = 1 << 2
}

/// Draw order. A scoring file slots between the back and front of the Trash so it drops *into* it.
enum Z {
    static let basketBack: CGFloat = 1
    static let fileInside: CGFloat = 2
    static let basketFront: CGFloat = 3
    static let file: CGFloat = 10
}

/// How the Trash behaves in shoot mode.
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

/// How a file went in, for the callout.
struct MakeInfo {
    /// From where the file was let go to the opening, in points.
    let distance: CGFloat
    /// Didn't touch the can on the way in.
    let isClean: Bool
    /// Dropped straight onto the Trash.
    let isDunk: Bool
}

/// The whole screen is the court and the Trash is the basket. Thrown files fly with the momentum
/// of the drag; into the Trash they go to the Trash, otherwise they stay where they land.
final class CourtScene: SKScene, SKPhysicsContactDelegate {
    /// A file went in: trash it.
    var onScore: ((_ url: URL, _ make: MakeInfo) -> Void)?
    /// A file came to rest outside the Trash at this point. False for a file popping out after an undo.
    var onLand: ((_ url: URL, _ point: CGPoint, _ wasThrown: Bool) -> Void)?
    /// The player dragged the Trash somewhere new (the bottom of the can, in scene coordinates).
    var onBasketMoved: ((CGPoint) -> Void)?
    var mode = Mode.normal {
        didSet { if mode != oldValue { modeChanged() } }
    }
    var basketSize = BasketSize.medium {
        didSet { if basketSize != oldValue { resizeBasket() } }
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
    /// Where the Trash rests (the bottom of the can) when it isn't moving or dodging.
    private var home = CGPoint.zero
    /// The Trash tile in the Dock while the basket sits on it; dropping a file there is a dunk.
    private var dockTile: CGRect?
    private var grabOffset: CGVector?
    private var movingPhase: CGFloat = 0
    private var now: TimeInterval = 0
    private var elapsed: TimeInterval = 0

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
        basket.setScale(dockTile.map { $0.height / basket.side } ?? 0.3)
        let grow = SKAction.scale(to: 1, duration: 0.4)
        grow.timingFunction = { t in Float(1 - pow(1 - Double(t), 3) * cos(Double(t) * 5)) } // overshoot, settle
        basket.run(grow)
    }

    /// The Dock-sized Trash stays in the Dock, so only grown ones can be grabbed.
    func isOverBasket(_ point: CGPoint) -> Bool {
        guard let basket, basketSize != .dock else { return false }
        return basket.covers(offset(of: point, from: basket))
    }

    /// Launches dropped files from `point` with the drag's velocity. Dropping right on the Trash is a dunk.
    func throwFiles(_ urls: [URL], at point: CGPoint, velocity: CGVector) {
        var dunk = isOnBasket(point)
        if dunk, mode == .impossible, let basket {
            dodge(awayFrom: point.x, basket: basket, instantly: true)
            dunk = false
        }
        let speed = hypot(velocity.dx, velocity.dy)
        let scale = speed > Tuning.maxThrowSpeed ? Tuning.maxThrowSpeed / speed : 1
        if !dunk {
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
            addChild(file)
            if dunk, let basket {
                score(file, in: basket, isDunk: true)
            } else {
                let damping = 1 - CGFloat(index) * 0.04
                file.physicsBody?.velocity = CGVector(dx: velocity.dx * scale * damping, dy: velocity.dy * scale * damping)
                if isOnFire { file.ignite() }
            }
        }
    }

    /// After an undo: the file pops back out of the Trash, towards the middle of the screen.
    func respawn(_ url: URL) {
        guard let basket else { return }
        let file = FileNode(url: url)
        file.canScore = false
        file.position = CGPoint(x: basket.position.x, y: basket.position.y + basket.rimHeight + FileNode.radius + 6)
        file.alpha = 0
        addChild(file)
        let direction: CGFloat = basket.position.x > size.width / 2 ? -1 : 1
        file.physicsBody?.velocity = CGVector(dx: direction * .random(in: 260...360), dy: 700)
        file.run(.fadeIn(withDuration: 0.12))
        if let isFull = Self.trashHasItems() { basket.isFull = isFull }
    }

    func clear() {
        for node in children where node is FileNode || node is FlameTrail { node.removeFromParent() }
        grabOffset = nil
    }

    // MARK: Dragging the Trash

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard isOverBasket(point), let basket else { return }
        basket.removeAction(forKey: ActionKey.dash)
        basket.removeAction(forKey: ActionKey.home)
        grabOffset = CGVector(dx: basket.position.x - point.x, dy: basket.position.y - point.y)
        basket.run(.scale(to: 1.06, duration: 0.1))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let basket, let grabOffset else { return }
        let point = event.location(in: self)
        basket.position = clampedHome(CGPoint(x: point.x + grabOffset.dx, y: point.y + grabOffset.dy), for: basket)
    }

    override func mouseUp(with event: NSEvent) {
        guard let basket, grabOffset != nil else { return }
        grabOffset = nil
        basket.run(.scale(to: 1, duration: 0.15))
        home = basket.position
        dockTile = nil
        syncMovingPhase()
        onBasketMoved?(home)
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        elapsed = now > 0 ? min(currentTime - now, 0.1) : 0
        now = currentTime
        if mode == .moving, grabOffset == nil, let basket {
            movingPhase += CGFloat(elapsed) * 2 * .pi / Tuning.movingPeriod
            basket.position = CGPoint(x: trackCenter + trackAmplitude * sin(movingPhase), y: home.y)
        }
    }

    override func didSimulatePhysics() {
        if mode == .impossible, grabOffset == nil, let basket, basket.action(forKey: ActionKey.dash) == nil,
           let incoming = incomingDrop(into: basket) {
            dodge(awayFrom: incoming, basket: basket)
        }
        for file in fileNodes where !file.isLeaving {
            let velocity = file.physicsBody?.velocity ?? .zero
            // The can's sides are solid, so a file whose centre is inside it came in through the top.
            if let basket, file.canScore, basket.isInside(offset(of: file.position, from: basket)) {
                score(file, in: basket)
                continue
            }
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
        if categories & Physics.rim != 0, impulse > 0.05 {
            sounds.play(.clank, volume: min(1, impulse / 0.8))
            (contact.bodyA.node as? FileNode ?? contact.bodyB.node as? FileNode)?.hitRim = true
        } else if categories & Physics.wall != 0, impulse > 0.15 {
            sounds.play(.thud, volume: min(0.9, impulse))
        }
    }

    // MARK: Scoring

    private func score(_ file: FileNode, in basket: BasketNode, isDunk: Bool = false) {
        file.isLeaving = true
        file.physicsBody = nil
        file.zPosition = Z.fileInside
        file.extinguish()
        let opening = CGPoint(x: basket.position.x, y: basket.position.y + basket.rimHeight)
        let make = MakeInfo(
            distance: hypot(opening.x - file.releasePoint.x, opening.y - file.releasePoint.y),
            // The Dock-sized Trash has no rim to touch, so nothing it catches is clean.
            isClean: basket.isSolid && !file.hitRim,
            isDunk: isDunk
        )
        // Trash it right away, so Finder's sound lands with the file.
        onScore?(file.url, make)

        let target = CGPoint(x: basket.position.x, y: basket.position.y + basket.rimHeight * 0.45)
        let drop = SKAction.move(to: target, duration: 0.26)
        drop.timingMode = .easeIn
        let fade = SKAction.sequence([.wait(forDuration: 0.14), .fadeOut(withDuration: 0.12)])
        file.run(.group([drop, .scale(to: basket.isSolid ? 0.55 : 0.3, duration: 0.26), fade])) { [weak basket] in
            file.removeFromParent()
            basket?.bump()
            basket?.isFull = true
        }
    }

    /// A miss: the file stays where it came to rest (for a desktop file, its real icon moves there).
    private func land(_ file: FileNode) {
        file.isLeaving = true
        file.physicsBody = nil
        file.extinguish()
        onLand?(file.url, file.position, file.canScore)
        file.run(.sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    // MARK: Moving and impossible modes

    private var trackCenter: CGFloat { size.width / 2 }
    private var trackAmplitude: CGFloat { max(0, size.width / 2 - (basket?.outerHalfWidth ?? 60) - 40) }

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
        let margin = basket.outerHalfWidth + 20
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
        old?.removeFromParent()
        addChild(basket)
        self.basket = basket
        return basket
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

    /// Dropped onto the can itself, or onto the Trash tile in the Dock.
    private func isOnBasket(_ point: CGPoint) -> Bool {
        guard let basket else { return false }
        return basket.isInside(offset(of: point, from: basket)) || dockTile?.insetBy(dx: -6, dy: -6).contains(point) == true
    }

    private func offset(of point: CGPoint, from basket: BasketNode) -> CGPoint {
        CGPoint(x: point.x - basket.position.x, y: point.y - basket.position.y)
    }

    private func clampedHome(_ point: CGPoint, for basket: BasketNode) -> CGPoint {
        let margin = basket.outerHalfWidth + 10
        return CGPoint(
            x: min(max(point.x, margin), size.width - margin),
            y: min(max(point.y, 0), size.height - basket.side)
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
