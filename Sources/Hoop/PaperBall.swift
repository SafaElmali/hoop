import SpriteKit

/// A Shot Clock practice ball: a sheet of paper crumpled into a ball, drawn in code. It flies like a
/// thrown file, but nothing real goes anywhere when it's in.
final class PaperBall: Throwable {
    private static let texture = SKTexture(cgImage: drawing())

    private let paper = SKSpriteNode(texture: PaperBall.texture)

    override init() {
        super.init()
        paper.size = CGSize(width: Self.radius * 2 + 4, height: Self.radius * 2 + 4)
        // Each one turned its own way, so a rackful doesn't look stamped out.
        paper.zRotation = .random(in: 0..<(2 * .pi))
        addChild(paper)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Rolls with horizontal speed.
    override func updateLook() {
        paper.zRotation -= (physicsBody?.velocity.dx ?? 0) / 5000
    }

    /// Off-white paper lit from the top left: a lumpy outline, flat facets catching more or less
    /// light, and a few creases (a dark fold with a bright edge beside it). Always crumpled the same way.
    private static func drawing() -> CGImage {
        let scale: CGFloat = 3
        let side = (radius + 2) * 2
        let context = CGContext(data: nil, width: Int(side * scale), height: Int(side * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        var random = Crumple(state: 0x9E37_79B9_7F4A_7C15)
        let center = CGPoint(x: side / 2, y: side / 2)
        let light = CGPoint(x: center.x - radius * 0.35, y: center.y + radius * 0.4)

        let corners = (0..<14).map { index -> CGPoint in
            let angle = (CGFloat(index) + .random(in: -0.25...0.25, using: &random)) / 14 * 2 * .pi
            let distance = radius * .random(in: 0.9...1, using: &random)
            return CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
        }
        let outline = CGMutablePath()
        outline.move(to: midpoint(corners[corners.count - 1], corners[0]))
        for (index, corner) in corners.enumerated() {
            outline.addQuadCurve(to: midpoint(corner, corners[(index + 1) % corners.count]), control: corner)
        }
        outline.closeSubpath()

        context.saveGState()
        context.addPath(outline)
        context.clip()
        let paper = [NSColor(hex: 0xFFFEFA), NSColor(hex: 0xF0EDE3), NSColor(hex: 0xC2BCAC)].map(\.cgColor) as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: paper, locations: [0, 0.5, 1])!
        context.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: center, endRadius: radius * 1.05, options: [.drawsAfterEndLocation])

        // Ridges, where folds meet: one near the middle, the rest spread around it. Each facet is a
        // wedge from the edge to its nearest ridge, or between ridges.
        let ridges = (0..<7).map { index -> CGPoint in
            let angle = CGFloat(index) / 7 * 2 * .pi + .random(in: -0.4...0.4, using: &random)
            let distance = radius * (index == 0 ? 0.1 : .random(in: 0.35...0.65, using: &random))
            return CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
        }
        let nearestRidge = { (point: CGPoint) in ridges.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }! }
        var facets = corners.indices.map { index in
            let corner = corners[index], next = corners[(index + 1) % corners.count]
            return [nearestRidge(midpoint(corner, next)), corner, next]
        }
        facets += ridges.indices.map { [ridges[$0], ridges[($0 + 1) % ridges.count], ridges[0]] }
        for facet in facets {
            // Facets facing the light catch more of it, give or take how they were crumpled.
            let middle = CGPoint(x: facet.map(\.x).reduce(0, +) / 3, y: facet.map(\.y).reduce(0, +) / 3)
            let facing = ((middle.x - center.x) * -0.6 + (middle.y - center.y) * 0.8) / radius
            let shade = facing + .random(in: -0.7...0.7, using: &random)
            context.addLines(between: facet)
            context.closePath()
            context.setFillColor(shade > 0 ? CGColor(gray: 1, alpha: min(0.6, shade * 0.45)) : CGColor(gray: 0.25, alpha: min(0.24, -shade * 0.2)))
            context.fillPath()
        }

        var creases: [(CGPoint, CGPoint)] = []
        for (index, ridge) in ridges.enumerated() {
            creases.append((ridge, corners[(index * 2 + 1) % corners.count]))
            if index > 0, index.isMultiple(of: 2) { creases.append((ridge, ridges[index - 1])) }
        }
        for (start, end) in creases {
            // A slight kink partway along, like a real fold.
            let kink = CGPoint(x: (start.x + end.x) / 2 + .random(in: -0.8...0.8, using: &random), y: (start.y + end.y) / 2 + .random(in: -0.8...0.8, using: &random))
            for (offset, color, width) in [(CGFloat(0), CGColor(srgbRed: 0.45, green: 0.42, blue: 0.36, alpha: 0.3), CGFloat(0.5)),
                                           (0.45, CGColor(gray: 1, alpha: 0.7), 0.5)] {
                context.addLines(between: [start, kink, end].map { CGPoint(x: $0.x + offset, y: $0.y - offset) })
                context.setStrokeColor(color)
                context.setLineWidth(width)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        }
        context.restoreGState()

        // A soft edge, so the ball still reads over a white window.
        context.addPath(outline)
        context.setStrokeColor(NSColor(hex: 0xA39D8E).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        return context.makeImage()!
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

/// Repeatable random numbers (xorshift64), so the paper is crumpled the same way every launch.
private struct Crumple: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
