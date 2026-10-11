import CoreGraphics
import Foundation

/// A diamond-mesh basketball net hanging from a rim ellipse centred at the origin (y up).
/// Shared by the live hoop and the app icon.
enum NetGeometry {
    typealias Segment = (a: CGPoint, b: CGPoint)

    private static let strands = 14
    private static let rows = 5

    /// Splits the mesh into strands in front of and behind the ball's path.
    /// `swing` > 0 stretches and pinches the net (ball passing through); < 0 is the recoil.
    static func segments(rx: CGFloat, ry: CGFloat, height: CGFloat, swing: CGFloat = 0) -> (front: [Segment], back: [Segment]) {
        func vertex(_ row: Int, _ strand: Int) -> (point: CGPoint, depth: CGFloat) {
            let t = CGFloat(row) / CGFloat(rows)
            let taper = (1 - 0.4 * pow(t, 1.2)) * (1 - 0.25 * swing * t)
            let angle = (CGFloat(strand) + (row.isMultiple(of: 2) ? 0 : 0.5)) / CGFloat(strands) * 2 * .pi
            let y = -height * t * (1 + 0.3 * swing * t) + ry * taper * sin(angle)
            return (CGPoint(x: rx * taper * cos(angle), y: y), sin(angle))
        }

        var front: [Segment] = []
        var back: [Segment] = []
        for row in 0..<rows {
            for strand in 0..<strands {
                let top = vertex(row, strand)
                let neighbours = row.isMultiple(of: 2) ? [strand - 1, strand] : [strand, strand + 1]
                for neighbour in neighbours {
                    let bottom = vertex(row + 1, (neighbour + strands) % strands)
                    if top.depth + bottom.depth < 0 {
                        front.append((top.point, bottom.point))
                    } else {
                        back.append((top.point, bottom.point))
                    }
                }
            }
        }
        return (front, back)
    }
}

extension CGPath {
    static func lines(_ segments: [NetGeometry.Segment]) -> CGPath {
        let path = CGMutablePath()
        for segment in segments {
            path.move(to: segment.a)
            path.addLine(to: segment.b)
        }
        return path
    }

    /// Part of an ellipse centred at the origin; angles in radians, 0…π is the back (top) half.
    static func ellipseArc(radii: CGSize, from start: CGFloat, to end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let steps = 48
        for step in 0...steps {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: radii.width * cos(angle), y: radii.height * sin(angle))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
