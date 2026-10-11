import AppKit
import SpriteKit

/// A see-through panel over the whole screen (and the Dock) where the game is drawn. It lets clicks
/// through so the desktop keeps working, except over the Trash and the folder hoop (so they can be
/// dragged) and while a file drag is in progress: then it becomes the drop target and turns the drag
/// into a throw. Non-activating, so grabbing the Trash doesn't pull focus from the app you're in.
final class OverlayWindow: NSPanel {
    private(set) var isArmed = false

    private let court = CourtView(frame: .zero)
    private var pollTimer: Timer?
    private var isMouseDown = false
    private var pasteboardBaseline = 0
    private var scene: CourtScene? { court.scene as? CourtScene }

    init(scene: CourtScene) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Just above the Dock so the grown Trash draws over it, still below the menu bar.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        contentView = court
        court.presentScene(scene)
        court.isPaused = true
    }

    /// `home` is the bottom of the can and `dockTile` the Trash in the Dock, in screen coordinates.
    func show(on screen: NSScreen, home: CGPoint, dockTile: CGRect?) {
        setFrame(screen.frame, display: false)
        moveBasket(home: home, dockTile: dockTile, animated: true)
        court.isPaused = false
        orderFrontRegardless()
        pasteboardBaseline = NSPasteboard(name: .drag).changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.watchPointer() }
    }

    func hide() {
        pollTimer?.invalidate()
        pollTimer = nil
        disarm()
        orderOut(nil)
        scene?.clear()
        court.isPaused = true
    }

    func moveBasket(home: CGPoint, dockTile: CGRect?, animated: Bool) {
        scene?.mountBasket(home: scenePoint(fromScreen: home), dockTile: dockTile.map(sceneRect(fromScreen:)), animated: animated)
    }

    /// `rimCenter` is the middle of the folder hoop's rim, in screen coordinates; a nil `folder` takes the hoop down.
    func mountHoop(folder: URL?, rimCenter: CGPoint, animated: Bool) {
        scene?.mountHoop(folder: folder, rimCenter: scenePoint(fromScreen: rimCenter), animated: animated)
    }

    func screenPoint(fromScene point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + frame.minX, y: point.y + frame.minY)
    }

    func disarm() {
        isArmed = false
        ignoresMouseEvents = true
    }

    /// Finder owns the drag, so we can't catch its start directly. Instead we watch for the drag
    /// pasteboard to change while the button is held, and only then start taking mouse input.
    private func watchPointer() {
        let isDown = NSEvent.pressedMouseButtons & 1 != 0
        let changeCount = NSPasteboard(name: .drag).changeCount
        if isDown, !isMouseDown {
            isMouseDown = true
            pasteboardBaseline = changeCount
            Log.event("mouse down, drag pasteboard \(changeCount)")
        } else if !isDown, isMouseDown {
            isMouseDown = false
            Log.event("mouse up, armed=\(isArmed)")
            // Safety net in case the drag ended somewhere we never heard about.
            if isArmed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    if NSEvent.pressedMouseButtons & 1 == 0 { self?.disarm() }
                }
            }
        }
        if isMouseDown, !isArmed, changeCount != pasteboardBaseline {
            Log.event("drag started (pasteboard \(pasteboardBaseline) → \(changeCount)): taking the drop")
            isArmed = true
            ignoresMouseEvents = false
        } else if !isMouseDown, !isArmed {
            // Take clicks only over the Trash and the folder hoop, so they can be dragged around.
            let overGoal = scene?.isOverGoal(scenePoint(fromScreen: NSEvent.mouseLocation)) ?? false
            if ignoresMouseEvents == overGoal { ignoresMouseEvents = !overGoal }
        }
    }

    private func scenePoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }

    private func sceneRect(fromScreen rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }
}

/// SpriteKit view that receives the dragged files and measures how fast they were moving.
final class CourtView: SKView {
    private var samples: [(point: CGPoint, time: TimeInterval)] = []
    private var overlay: OverlayWindow? { window as? OverlayWindow }
    private var court: CourtScene? { scene as? CourtScene }

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowsTransparency = true
        ignoresSiblingOrder = true
        preferredFramesPerSecond = 120
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Lets you grab the Trash straight away, while another app is active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Not files (e.g. dragged text): step aside so the drop reaches the app underneath.
        guard !fileURLs(in: sender).isEmpty else {
            Log.event("drag entered without files: stepping aside")
            overlay?.disarm()
            return []
        }
        Log.event("drag entered with \(fileURLs(in: sender).count) file(s)")
        samples = []
        record(sender)
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        record(sender)
        return operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        record(sender)
        let urls = fileURLs(in: sender)
        guard let court, !urls.isEmpty else { return false }
        Log.event("drop at \(scenePoint(sender)), velocity \(flickVelocity())")
        court.throwFiles(urls, at: scenePoint(sender), velocity: flickVelocity())
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        samples = []
        overlay?.disarm()
    }

    /// Never `.move`: the throw decides what happens to the file, not the drop.
    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        info.draggingSourceOperationMask.contains(.generic) ? .generic : .copy
    }

    private func record(_ info: NSDraggingInfo) {
        let time = ProcessInfo.processInfo.systemUptime
        samples.append((scenePoint(info), time))
        samples.removeAll { time - $0.time > 0.12 }
    }

    /// Average velocity over the last ~80 ms, so a drag that stopped before release just drops.
    private func flickVelocity() -> CGVector {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time < 0.08 }),
              last.time - first.time > 0.005
        else { return .zero }
        let elapsed = last.time - first.time
        return CGVector(dx: (last.point.x - first.point.x) / elapsed, dy: (last.point.y - first.point.y) / elapsed)
    }

    private func scenePoint(_ info: NSDraggingInfo) -> CGPoint {
        let point = convert(info.draggingLocation, from: nil)
        return court?.convertPoint(fromView: point) ?? point
    }

    private func fileURLs(in info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
