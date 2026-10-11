import SpriteKit

/// Where a made file goes.
enum Target: Equatable {
    /// The Trash, through Finder.
    case trash
    /// Into this folder, through the folder hoop.
    case folder(URL)
}

/// Something files are thrown into: the Trash or the folder hoop. Points are relative to the
/// node's position, which is in scene coordinates.
protocol Goal: SKNode {
    /// Where a file that goes in ends up.
    var target: Target { get }
    /// The middle of the opening.
    var opening: CGPoint { get }
    /// Whether there's a rim to miss; nothing a goal without one catches is clean.
    var hasRim: Bool { get }
    /// What has to stay on screen while it's dragged around.
    var extent: CGRect { get }

    /// Whether a file whose centre went from `start` to `end` this frame went in.
    func takesIn(from start: CGPoint, to end: CGPoint) -> Bool
    /// Whether a file let go at `point` drops straight in: a dunk.
    func isDunk(at point: CGPoint) -> Bool
    /// Whether `point` is on the goal, for grabbing it.
    func covers(_ point: CGPoint) -> Bool
    /// Plays a made file going in, then removes it from the scene.
    func swallow(_ file: FileNode)
}
