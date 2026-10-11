import SpriteKit

/// Flames streaming off a file (or paper ball) thrown while on fire. They're left behind in `world`,
/// so they trace the flight instead of following the file around.
final class FlameTrail: SKEmitterNode {
    private static let lifetime: CGFloat = 0.4
    private static let lifetimeRange: CGFloat = 0.15

    /// A soft white dot; the color ramp tints it.
    private static let dot: SKTexture = {
        let side = 64
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        let center = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(side) / 2, options: [])
        return SKTexture(cgImage: context.makeImage()!)
    }()

    init(leavingIn world: SKNode) {
        super.init()
        targetNode = world
        particleTexture = Self.dot
        particleBirthRate = 260
        particleLifetime = Self.lifetime
        particleLifetimeRange = Self.lifetimeRange
        particlePositionRange = CGVector(dx: Throwable.radius * 0.75, dy: Throwable.radius * 0.75)
        particleSpeed = 30
        particleSpeedRange = 30
        emissionAngleRange = 2 * .pi
        yAcceleration = 220 // flames rise
        particleSize = CGSize(width: 34, height: 34)
        particleScaleRange = 0.35
        particleScaleSpeed = -1.6
        particleBlendMode = .alpha
        particleColorBlendFactor = 1
        // Hot yellow at the file, cooling to orange, then gone.
        particleColorSequence = SKKeyframeSequence(
            keyframeValues: [NSColor(hex: 0xFFE680), NSColor(hex: 0xFF8A1F), NSColor(hex: 0xF0461A)],
            times: [0, 0.4, 1]
        )
        particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0.95, 0.8, 0], times: [0, 0.5, 1])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Stops new flames; the ones already in the air burn out where they are.
    func burnOut() {
        guard let world = targetNode, parent != nil else { return removeFromParent() }
        particleBirthRate = 0
        move(toParent: world)
        run(.sequence([.wait(forDuration: TimeInterval(Self.lifetime + Self.lifetimeRange / 2)), .removeFromParent()]))
    }
}
