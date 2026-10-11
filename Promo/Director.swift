import AppKit
import SpriteKit

/// Plays a scripted session of Hoop on the fake desktop, driving the real game scene,
/// and renders it to an MP4 with sound.
final class Director {
    static let fps = 60.0
    static let duration: TimeInterval = 37
    static let pixelSize = (width: 1920, height: 1080)

    private enum Aim {
        /// Into the middle of the opening.
        case center
        /// Onto the left lip, for a rim-out.
        case leftLip
        /// Where a Moving-mode Trash will be when the file comes down.
        case lead
    }

    /// The cursor holds an icon a little left of and above its centre.
    private static let grabOffset = CGVector(dx: -6, dy: 6)
    /// Matches CourtScene: 11 m/s² at 150 points per metre, and FileNode's damping.
    private static let gravity: CGFloat = -11 * 150
    private static let damping: CGFloat = 0.1
    /// Matches CourtScene's Moving mode.
    private static let movingPeriod: CGFloat = 8

    private let log = SoundLog()
    private let files: PromoFiles
    private let scene: CourtScene
    private let stage: Stage
    private var beats: [(time: TimeInterval, run: () -> Void)] = []
    private var reactions: [URL: (score: () -> Void, land: () -> Void)] = [:]
    private var cheers = ["Swish!", "Buckets!", "Splash!", "Count it!"]
    private var denials = ["Denied!", "Nope", "Not today"]
    private var now: TimeInterval = 0
    private var lastBasketX: CGFloat?
    private var basketMovingLeft = false

    init() throws {
        files = try PromoFiles()
        scene = CourtScene(sounds: log)
        scene.size = Stage.size
        scene.scaleMode = .fill
        stage = Stage(scene: scene)

        let layout: [(URL, CGPoint)] = [
            (files.screenshot, CGPoint(x: 420, y: 560)), (files.psd, CGPoint(x: 250, y: 370)),
            (files.resume, CGPoint(x: 700, y: 690)), (files.photo, CGPoint(x: 560, y: 300)),
            (files.taxes, CGPoint(x: 310, y: 720)),
        ] + zip(files.clutter, [
            CGPoint(x: 1520, y: 810), CGPoint(x: 1410, y: 810), CGPoint(x: 1520, y: 705),
            CGPoint(x: 1520, y: 600), CGPoint(x: 1410, y: 705), CGPoint(x: 1520, y: 495),
        ])
        for (url, point) in layout { stage.place(url, at: point) }
        stage.cursor.position = CGPoint(x: 980, y: 430)

        scene.onScore = { [unowned self] url in
            log.play(.trash)
            stage.removeIcon(url)
            let cheer = cheers.isEmpty ? "Swish!" : cheers.removeFirst()
            stage.showToast(title: cheer, subtitle: "\(url.lastPathComponent.middleTruncated(to: 26)) → Trash", undo: true, for: 2.6)
            print(String(format: "%6.2fs  in the Trash   %@", now, url.lastPathComponent))
            reactions.removeValue(forKey: url)?.score()
        }
        scene.onLand = { [unowned self] url, point, _ in
            stage.moveIcon(url, to: point)
            if scene.mode == .impossible {
                let denial = denials.isEmpty ? "Denied!" : denials.removeFirst()
                stage.showToast(title: denial, subtitle: "Impossible mode never lets one in", for: 2.2)
            } else {
                stage.showToast(title: "Brick!", subtitle: "\(url.lastPathComponent.middleTruncated(to: 26)) stays where it landed", for: 2.2)
            }
            print(String(format: "%6.2fs  landed         %@", now, url.lastPathComponent))
            reactions.removeValue(forKey: url)?.land()
        }
        writeScript()
    }

    // MARK: The script

    private func writeScript() {
        let stage = stage
        beat(0.2) { stage.showCaption("my desktop after one (1) week") }
        beat(2.4) {
            stage.hideCaption()
            stage.showKeys(["⌃", "⌥", "H"])
            self.log.click()
        }
        beat(2.9) {
            self.startShooting()
            stage.showCaption("so I turned the Trash into a hoop")
        }

        throwFile(files.screenshot, at: 4.2, release: { _ in CGPoint(x: 560, y: 470) }, flight: 1.25, aim: .center,
                  onScore: { stage.showCaption("nothing but net") })
        throwFile(files.psd, at: 7.5, release: { _ in CGPoint(x: 380, y: 430) }, flight: 1.2, aim: .leftLip)
        beat(10.0) { stage.showCaption("…that one was on purpose") }

        beat(12.0) { stage.showCaption("skill issue? there’s a Huge size") }
        pickMenu(at: 12.2, title: "Trash Size", items: BasketSize.allCases.map(\.title), selected: 1, choice: 3) {
            self.scene.basketSize = .huge
        }
        throwFile(files.resume, at: 14.0, release: { _ in CGPoint(x: 760, y: 640) }, flight: 1.15, aim: .center,
                  onScore: { stage.showCaption("ez") })

        beat(17.0) { stage.showCaption("too easy. Moving mode") }
        pickMenu(at: 17.2, title: "Mode", items: Mode.allCases.map(\.title), selected: 0, choice: 1) { self.setMode(.moving) }
        throwFile(files.photo, at: 18.8, release: { _ in CGPoint(x: 650, y: 380) }, flight: 1.2, aim: .lead,
                  onScore: { stage.showCaption("still got it") })

        beat(22.0) { stage.showCaption("Impossible mode") }
        pickMenu(at: 22.2, title: "Mode", items: Mode.allCases.map(\.title), selected: 1, choice: 2) { self.setMode(.impossible) }
        throwFile(files.taxes, at: 23.8, release: { _ in CGPoint(x: 430, y: 640) }, flight: 1.25, aim: .center,
                  onLand: { stage.showCaption("it really doesn’t want my taxes") })
        dunk(files.taxes, at: 28.4, onLand: { stage.showCaption("IT. DOES. NOT. WANT. MY. TAXES.") })

        beat(33.6) {
            stage.hideCaption()
            stage.hideToast()
            stage.showEndCard()
        }
    }

    private func startShooting() {
        let tile = stage.trashTile
        scene.mountBasket(home: BasketNode.base(onDockTile: tile), dockTile: tile, animated: true)
        stage.setShooting(true)
        stage.showToast(title: "Shoot mode · Normal", subtitle: "Throw files into the Trash · drag the Trash to move it · esc to stop")
    }

    private func setMode(_ mode: Mode) {
        scene.mode = mode
        let hint = mode == .moving ? "The Trash is on the move · esc to stop" : "Good luck · esc to stop"
        stage.showToast(title: "Shoot mode · \(mode.title)", subtitle: hint)
    }

    // MARK: Moves

    private func beat(_ time: TimeInterval, _ run: @escaping () -> Void) {
        beats.append((time, run))
    }

    private func moveCursor(to point: CGPoint, duration: TimeInterval, timing: SKActionTimingMode = .easeInEaseOut) {
        let move = SKAction.move(to: point, duration: duration)
        move.timingMode = timing
        stage.cursor.run(move, withKey: "move")
    }

    /// Grab an icon, wind up, and flick it through `release` at the speed that lands it on `aim`.
    private func throwFile(_ url: URL, at start: TimeInterval, release: @escaping (CGPoint) -> CGPoint, flight: CGFloat, aim: Aim,
                           onScore: @escaping () -> Void = {}, onLand: @escaping () -> Void = {}) {
        let offset = Self.grabOffset
        var releasePoint = CGPoint.zero
        var velocity = CGVector.zero
        beat(start) {
            guard let icon = self.stage.icons[url] else { return }
            self.moveCursor(to: CGPoint(x: icon.position.x - offset.dx, y: icon.position.y - offset.dy), duration: 0.45)
        }
        beat(start + 0.5) {
            guard let icon = self.stage.icons[url] else { return }
            self.log.click()
            self.stage.pickUp(url)
            releasePoint = release(icon.position)
            velocity = self.velocity(from: releasePoint, flight: flight, aim: aim, releasingIn: 0.6)
            let windUp = CGPoint(x: releasePoint.x - velocity.dx * 0.1 - offset.dx, y: releasePoint.y - velocity.dy * 0.1 - offset.dy)
            self.moveCursor(to: windUp, duration: 0.45)
        }
        beat(start + 1.0) {
            self.moveCursor(to: CGPoint(x: releasePoint.x - offset.dx, y: releasePoint.y - offset.dy), duration: 0.1, timing: .linear)
        }
        beat(start + 1.1) {
            let center = self.stage.letGo()
            self.reactions[url] = (onScore, onLand)
            self.scene.throwFiles([url], at: center, velocity: velocity)
            // Give QuickLook a moment so the flying file shows its preview from the first frame.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        }
    }

    /// Carry an icon straight onto the Trash and let go.
    private func dunk(_ url: URL, at start: TimeInterval, onLand: @escaping () -> Void) {
        let offset = Self.grabOffset
        beat(start) {
            guard let icon = self.stage.icons[url] else { return }
            self.moveCursor(to: CGPoint(x: icon.position.x - offset.dx, y: icon.position.y - offset.dy), duration: 0.45)
        }
        beat(start + 0.5) {
            guard let basket = self.stage.basket else { return }
            self.log.click()
            self.stage.pickUp(url)
            let opening = CGPoint(x: basket.position.x, y: basket.position.y + basket.rimHeight * 0.55)
            self.moveCursor(to: CGPoint(x: opening.x - offset.dx, y: opening.y - offset.dy), duration: 1.1)
        }
        beat(start + 1.75) {
            let center = self.stage.letGo()
            self.reactions[url] = ({}, onLand)
            self.scene.throwFiles([url], at: center, velocity: .zero)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        }
    }

    /// Open a 🏀 menu, move to a row and click it.
    private func pickMenu(at start: TimeInterval, title: String, items: [String], selected: Int, choice: Int, apply: @escaping () -> Void) {
        var rows: [CGPoint] = []
        beat(start) { self.moveCursor(to: self.stage.statusIconPosition, duration: 0.5) }
        beat(start + 0.55) {
            self.log.click()
            rows = self.stage.showMenu(title: title, items: items, selected: selected)
        }
        beat(start + 0.75) { self.moveCursor(to: rows[choice], duration: 0.4) }
        beat(start + 1.05) { self.stage.highlightMenuRow(choice) }
        beat(start + 1.35) {
            self.log.click()
            self.stage.hideMenu()
            apply()
        }
    }

    // MARK: Aiming

    private func velocity(from point: CGPoint, flight: CGFloat, aim: Aim, releasingIn delay: TimeInterval) -> CGVector {
        guard let basket = stage.basket else { return .zero }
        let rimY = basket.position.y + basket.rimHeight
        let target = switch aim {
        case .center: CGPoint(x: basket.position.x, y: rimY + 10)
        case .leftLip: CGPoint(x: basket.position.x - basket.outerHalfWidth + 2, y: rimY + 14)
        case .lead: CGPoint(x: predictedBasketX(after: delay + Double(flight), basket: basket), y: rimY + 10)
        }
        return Self.launch(from: point, to: target, flight: flight)
    }

    /// The velocity that carries a damped projectile from `start` to `target` in `flight` seconds.
    private static func launch(from start: CGPoint, to target: CGPoint, flight: CGFloat) -> CGVector {
        let k = damping, g = gravity
        let reach = (1 - exp(-k * flight)) / k
        return CGVector(dx: (target.x - start.x) / reach, dy: (target.y - start.y - g * flight / k) / reach + g / k)
    }

    /// Where the gliding Trash will be in `seconds`, from its current position and direction.
    private func predictedBasketX(after seconds: TimeInterval, basket: BasketNode) -> CGFloat {
        let center = Stage.size.width / 2
        let amplitude = Stage.size.width / 2 - basket.outerHalfWidth - 40
        var phase = asin(max(-1, min(1, (basket.position.x - center) / amplitude)))
        if basketMovingLeft { phase = .pi - phase }
        return center + amplitude * sin(phase + 2 * .pi * CGFloat(seconds) / Self.movingPeriod)
    }

    // MARK: Rendering

    /// Renders the video to `output`, or with nil only simulates and prints what happens.
    func render(to output: URL?) throws {
        let frameCount = Int(Self.duration * Self.fps)
        let renderer = FrameRenderer(scene: scene, width: Self.pixelSize.width, height: Self.pixelSize.height)
        let silent = FileManager.default.temporaryDirectory.appending(path: "hoop-promo-video.mp4")
        var encoder: (process: Process, pipe: Pipe)?
        if output != nil {
            let pipe = Pipe()
            let process = try FFmpeg.start([
                "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(renderer.width)x\(renderer.height)", "-r", "\(Int(Self.fps))", "-i", "-",
                "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", silent.path,
            ], stdin: pipe)
            encoder = (process, pipe)
        }
        beats.sort { $0.time < $1.time }

        for frame in 0..<frameCount {
            now = Double(frame) / Self.fps
            log.now = now
            while let next = beats.first, next.time <= now {
                beats.removeFirst()
                next.run()
            }
            renderer.render(at: now, readBack: encoder != nil)
            trackBasket()
            if let encoder {
                renderer.pixels.withUnsafeBytes { encoder.pipe.fileHandleForWriting.write(Data($0)) }
                if frame % 120 == 0 { print("rendered \(frame / 60)s / \(Int(Self.duration))s") }
            }
            RunLoop.main.run(until: Date())
        }

        guard let output, let encoder else { return }
        try encoder.pipe.fileHandleForWriting.close()
        encoder.process.waitUntilExit()
        let soundtrack = FileManager.default.temporaryDirectory.appending(path: "hoop-promo-sound.wav")
        try log.writeSoundtrack(to: soundtrack, duration: Self.duration)
        try FFmpeg.run([
            "-i", silent.path, "-i", soundtrack.path, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest", "-movflags", "+faststart", output.path,
        ])
        print("wrote \(output.path)")
    }

    private func trackBasket() {
        guard let x = stage.basket?.position.x else { return }
        if let last = lastBasketX, x != last { basketMovingLeft = x < last }
        lastBasketX = x
    }
}
