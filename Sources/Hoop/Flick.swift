import CoreGraphics
import Foundation

/// How fast the pointer was moving when it let go: the average over the last ~80 ms, so a drag
/// that stopped before release just drops.
struct Flick {
    private var samples: [(point: CGPoint, time: TimeInterval)] = []

    var velocity: CGVector {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time < 0.08 }),
              last.time - first.time > 0.005
        else { return .zero }
        let elapsed = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / elapsed, dy: (last.point.y - first.point.y) / elapsed)
    }

    /// `time` is in seconds, on any steady clock (like `NSEvent.timestamp`).
    mutating func record(_ point: CGPoint, at time: TimeInterval) {
        samples.append((point, time))
        samples.removeAll { time - $0.time > 0.12 }
    }

    mutating func reset() {
        samples = []
    }
}
