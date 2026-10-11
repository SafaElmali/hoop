import AppKit
import SpriteKit

/// Plays a scripted session of Hoop on the fake desktop, driving the real game scene,
/// and renders it to an MP4 with sound.
final class Director {
    /// `funny` has meme captions and an end card; `gameplay` looks like a plain screen recording, with
    /// music; `features` is the same style showing streaks, the backboard, the folder hoop and Shot Clock.
    enum Cut {
        case funny, gameplay, features

        var duration: TimeInterval {
            switch self {
            case .funny: 37
            case .gameplay: 44
            case .features: 37
            }
        }
    }

    /// The 🏀 menu as the app shows it.
    private static let hoopMenu = ["Shoot Mode", "Shot Clock", "Mode", "Trash Size", "Backboard", "Folder Hoop",
                                   "Put Trash Back on Dock", "Undo", "Stats", "Sounds", "Shortcut…", "Open at Login", "Quit Hoop"]

    static let fps = 60.0
    static let pixelSize = (width: 1920, height: 1080)

    private enum Aim {
        /// Into the middle of the opening.
        case center
        /// Onto the left lip, for a rim-out.
        case leftLip
        /// Where a Moving-mode Trash will be when the file comes down.
        case lead
        /// Off the inside of the backboard, to drop back into the can.
        case bank
        /// Through the folder hoop.
        case hoop
    }

    /// The cursor holds an icon a little left of and above its centre.
    private static let grabOffset = CGVector(dx: -6, dy: 6)
    /// Matches CourtScene: 11 m/s² at 150 points per metre, and FileNode's damping.
    private static let gravity: CGFloat = -11 * 150
    private static let damping: CGFloat = 0.1
    /// Matches CourtScene's Moving mode.
    private static let movingPeriod: CGFloat = 8

    private let cut: Cut
    private let log = SoundLog()
    private let files: PromoFiles
    private let scene: CourtScene
    private let stage: Stage
    private var beats: [(time: TimeInterval, run: () -> Void)] = []
    private var reactions: [URL: (score: () -> Void, land: () -> Void)] = [:]
    private var cheers = ["Swish!", "Buckets!", "Splash!", "Count it!", "Nothing but net", "Money", "Swish!"]
    private var denials = ["Denied!", "Nope", "Not today"]
    private var now: TimeInterval = 0
    private var lastBasketX: CGFloat?
    private var basketMovingLeft = false
    /// The real callouts, for the features cut.
    private var scorekeeper: Scorekeeper?
    private var clock: ShotClock?
    /// While a paper ball is held it follows the cursor, one drag sample per frame.
    private var isHoldingBall = false

    init(cut: Cut) throws {
        self.cut = cut
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

        scene.onScore = { [unowned self] url, make in
            var destination = "Trash"
            if case let .folder(folder) = make.target {
                destination = folder.lastPathComponent
            } else {
                log.play(.trash)
            }
            stage.removeIcon(url)
            let callout = scorekeeper?.recordMake(make, bytes: 0)
            scene.isOnFire = scorekeeper?.isOnFire ?? false
            let title = callout?.title ?? (cheers.isEmpty ? "Swish!" : cheers.removeFirst())
            let subtitle = ["\(url.lastPathComponent.middleTruncated(to: 26)) → \(destination)", callout?.note].compactMap { $0 }.joined(separator: " · ")
            log.play(.make)
            stage.showToast(title: title, subtitle: subtitle, undo: true, for: 2.6)
            print(String(format: "%6.2fs  in → %@  %@  %@", now, destination, url.lastPathComponent, callout?.title ?? ""))
            reactions.removeValue(forKey: url)?.score()
        }
        scene.onLand = { [unowned self] url, point, wasThrown in
            stage.moveIcon(url, to: point)
            print(String(format: "%6.2fs  landed         %@", now, url.lastPathComponent))
            guard wasThrown else { return }
            let callout = scorekeeper?.recordMiss()
            scene.isOnFire = scorekeeper?.isOnFire ?? false
            if let callout {
                stage.showToast(title: callout.title, subtitle: "\(url.lastPathComponent.middleTruncated(to: 26)) stays where it landed", for: 2.2)
            } else if scene.mode == .impossible {
                let denial = denials.isEmpty ? "Denied!" : denials.removeFirst()
                stage.showToast(title: denial, subtitle: "Impossible mode never lets one in", for: 2.2)
            } else {
                stage.showToast(title: "Brick!", subtitle: "\(url.lastPathComponent.middleTruncated(to: 26)) stays where it landed", for: 2.2)
            }
            reactions.removeValue(forKey: url)?.land()
        }
        switch cut {
        case .funny: writeFunnyScript()
        case .gameplay: writeGameplayScript()
        case .features: writeFeaturesScript()
        }
    }

    // MARK: The scripts

    private func writeFunnyScript() {
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

    /// No captions: start from the 🏀 menu, a few makes and a miss, Undo, then every size and mode,
    /// ending on the real Dock-sized Trash.
    private func writeGameplayScript() {
        let clutterScreenshot = files.clutter[2], logo = files.clutter[5]
        pickMenu(at: 0.8, title: "Hoop", items: Self.hoopMenu, selected: -1, choice: 0) { self.startShooting() }

        throwFile(files.screenshot, at: 3.2, release: { _ in CGPoint(x: 560, y: 470) }, flight: 1.25, aim: .center)
        throwFile(files.psd, at: 6.2, release: { _ in CGPoint(x: 380, y: 430) }, flight: 1.2, aim: .leftLip)
        throwFile(files.resume, at: 9.0, release: { _ in CGPoint(x: 760, y: 640) }, flight: 1.15, aim: .center)
        clickUndo(at: 11.9, file: files.resume)
        throwFile(files.resume, at: 14.8, release: { icon in CGPoint(x: icon.x + 130, y: icon.y + 110) }, flight: 1.1, aim: .center)

        pickMenu(at: 17.8, title: "Trash Size", items: BasketSize.allCases.map(\.title), selected: 1, choice: 3) {
            self.scene.basketSize = .huge
        }
        throwFile(files.photo, at: 19.5, release: { _ in CGPoint(x: 650, y: 380) }, flight: 1.2, aim: .center)

        pickMenu(at: 22.4, title: "Mode", items: Mode.allCases.map(\.title), selected: 0, choice: 1) { self.setMode(.moving) }
        throwFile(files.taxes, at: 24.0, release: { _ in CGPoint(x: 430, y: 640) }, flight: 1.25, aim: .lead)

        pickMenu(at: 26.9, title: "Mode", items: Mode.allCases.map(\.title), selected: 1, choice: 2) { self.setMode(.impossible) }
        throwFile(clutterScreenshot, at: 28.6, release: { icon in CGPoint(x: icon.x - 300, y: icon.y - 40) }, flight: 1.0, aim: .center)
        dunk(clutterScreenshot, at: 33.0, onLand: {})

        pickMenu(at: 35.0, title: "Mode", items: Mode.allCases.map(\.title), selected: 2, choice: 0) { self.setMode(.normal) }
        pickMenu(at: 36.8, title: "Trash Size", items: BasketSize.allCases.map(\.title), selected: 3, choice: 4) {
            self.scene.basketSize = .dock
        }
        throwFile(logo, at: 38.6, release: { icon in CGPoint(x: icon.x - 330, y: icon.y + 40) }, flight: 1.2, aim: .center)

        beat(42.4) {
            self.stage.hideToast()
            self.stage.fadeToBlack(duration: 1.2)
        }
    }

    /// Only what's new: already in shoot mode two makes into a streak, it catches fire and burns
    /// out, the Arcade sound pack, a bank shot off the backboard, the folder hoop, a Shot Clock round
    /// with paper balls, and Stats.
    private func writeFeaturesScript() {
        let scorekeeper = Scorekeeper()
        scorekeeper.reset()
        for _ in 0..<2 { _ = scorekeeper.recordMake(MakeInfo(target: .trash, distance: 400, isClean: false, isDunk: false, isBank: false), bytes: 180_000) }
        self.scorekeeper = scorekeeper
        UserDefaults.standard.removeObject(forKey: "shotClockBest")
        scene.onPracticeScore = { [unowned self] make in practiceMade(make) }
        scene.onPracticeMiss = { [unowned self] in practiceMissed() }
        let downloads = FileManager.default.temporaryDirectory.appending(path: "hoop-promo-folders/Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let todo = files.clutter[4], screenshot3 = files.clutter[3]

        beat(0) {
            let tile = self.stage.trashTile
            self.scene.mountBasket(home: BasketNode.base(onDockTile: tile), dockTile: tile, animated: false)
            self.stage.setShooting(true)
            self.stage.showToast(title: "Shoot mode · Normal", subtitle: "Throw files into the Trash · drag the Trash to move it · esc to stop")
        }
        throwFile(files.photo, at: 0.4, release: { _ in CGPoint(x: 300, y: 430) }, flight: 1.4, aim: .center)
        throwFile(files.taxes, at: 3.2, release: { _ in CGPoint(x: 430, y: 640) }, flight: 1.25, aim: .center)
        throwFile(files.psd, at: 6.0, release: { _ in CGPoint(x: 380, y: 430) }, flight: 1.2, aim: .leftLip)

        pickMenu(at: 8.4, title: "Sounds", items: SoundPack.allCases.map(\.title), selected: 0, choice: 1) { self.log.pack = .arcade }
        pickMenu(at: 10.2, title: "Hoop", items: Self.hoopMenu, selected: -1, choice: 4) { self.scene.hasBackboard = true }
        throwFile(screenshot3, at: 12.0, release: { _ in CGPoint(x: 950, y: 520) }, flight: 1.0, aim: .bank)

        pickMenu(at: 14.6, title: "Folder Hoop", items: ["Off", "Downloads", "Desktop", "Documents", "Choose Folder…"], selected: 0, choice: 1) {
            self.scene.mountHoop(folder: downloads, rimCenter: CGPoint(x: Stage.size.width * 0.2, y: 305), animated: true)
        }
        throwFile(todo, at: 16.4, release: { _ in CGPoint(x: 900, y: 600) }, flight: 1.2, aim: .hoop)

        let roundStart = 19.2 + 1.35
        pickMenu(at: 19.2, title: "Hoop", items: Self.hoopMenu, selected: -1, choice: 1) { self.startShotClock(seconds: 10) }
        for second in 1...10 { beat(roundStart + Double(second)) { self.clock?.tick() } }
        throwBall(at: 20.9, release: CGPoint(x: 380, y: 470), flight: 1.25, aim: .center)
        throwBall(at: 22.9, release: CGPoint(x: 230, y: 420), flight: 0.9, aim: .hoop)
        throwBall(at: 24.9, release: CGPoint(x: 360, y: 480), flight: 1.25, aim: .center)
        throwBall(at: 26.9, release: CGPoint(x: 380, y: 470), flight: 1.25, aim: .center)

        beat(32.6) {
            let made = scorekeeper.makes, missed = scorekeeper.misses
            let rate = made + missed > 0 ? " · \(made * 100 / (made + missed))%" : ""
            let trashed = ByteCountFormatter.string(fromByteCount: Int64(scorekeeper.bytesTrashed), countStyle: .file)
            self.stage.showMenu(title: "Stats", items: ["Makes \(made) · Misses \(missed)\(rate)", "Best streak \(scorekeeper.bestStreak)", "Trashed \(trashed)", "Reset Stats"], selected: -1)
            self.moveCursor(to: CGPoint(x: self.stage.statusIconPosition.x + 40, y: self.stage.statusIconPosition.y - 60), duration: 0.5)
        }
        beat(35.0) {
            self.stage.hideMenu()
            self.stage.hideToast()
            self.stage.fadeToBlack(duration: 1.2)
        }
    }

    private func startShotClock(seconds: Int) {
        let clock = ShotClock(seconds: seconds) { [unowned self] clock in clockTicked(clock) }
        self.clock = clock
        log.play(.whistle)
        // Like the app: the rack stands at the bottom, on the side away from the Trash.
        scene.mountRack(center: CGPoint(x: 150, y: 96))
        stage.showToast(title: clock.hud.title, subtitle: clock.hud.subtitle)
    }

    /// Mirrors the app: the last five seconds tick; at zero the buzzer, the balls cleared, the result.
    private func clockTicked(_ clock: ShotClock) {
        guard clock.isOver else {
            if clock.secondsLeft <= 5 { log.play(.tick) }
            return stage.updateRestingToast(title: clock.hud.title, subtitle: clock.hud.subtitle)
        }
        log.play(.buzzer)
        self.clock = nil
        scene.clearPractice()
        stage.showToast(title: "Shoot mode · Normal", subtitle: "Throw files into the Trash · drag the Trash to move it · esc to stop")
        stage.showToast(title: clock.result.title, subtitle: clock.result.subtitle, for: 4)
    }

    private func practiceMade(_ make: MakeInfo) {
        guard let scorekeeper, let clock else { return }
        let callout = scorekeeper.recordMake(make, bytes: 0, isPractice: true)
        scene.isOnFire = scorekeeper.isOnFire
        clock.recordMake()
        if make.target == .trash { log.play(.trash) }
        log.play(.make)
        stage.showToast(title: callout.title, subtitle: ["\(clock.made) made", callout.note].compactMap { $0 }.joined(separator: " · "), for: 2)
        stage.updateRestingToast(title: clock.hud.title, subtitle: clock.hud.subtitle)
        print(String(format: "%6.2fs  paper ball in  %@", now, callout.title))
    }

    private func practiceMissed() {
        guard let scorekeeper, let clock else { return }
        let callout = scorekeeper.recordMiss(isPractice: true)
        scene.isOnFire = scorekeeper.isOnFire
        if let callout { stage.showToast(title: callout.title, subtitle: "\(clock.made) made", for: 2) }
        print(String(format: "%6.2fs  paper ball missed", now))
    }

    /// Grab a paper ball off the rack, wind up and flick it through `release` so it lands on `aim`.
    private func throwBall(at start: TimeInterval, release: CGPoint, flight: CGFloat, aim: Aim) {
        var velocity = CGVector.zero
        var ball = CGPoint.zero
        beat(start) {
            guard let position = self.scene.rackedBallPositions.first else { return }
            ball = position
            self.moveCursor(to: position, duration: 0.4)
        }
        beat(start + 0.45) {
            guard self.scene.pickUpBall(at: ball, time: self.now) else { return }
            self.log.click()
            self.isHoldingBall = true
            velocity = self.velocity(from: release, flight: flight, aim: aim, releasingIn: 0.55)
            self.moveCursor(to: CGPoint(x: release.x - velocity.dx * 0.1, y: release.y - velocity.dy * 0.1), duration: 0.4)
        }
        beat(start + 0.9) { self.moveCursor(to: release, duration: 0.1, timing: .linear) }
        beat(start + 1.0) {
            guard self.isHoldingBall else { return }
            self.isHoldingBall = false
            self.scene.releaseBall(at: self.stage.cursor.position, time: self.now)
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
        let hint = switch mode {
        case .normal: "Throw files into the Trash · drag the Trash to move it · esc to stop"
        case .moving: "The Trash is on the move · esc to stop"
        case .impossible: "Good luck · esc to stop"
        }
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

    /// Click Undo in the toast: the file pops back out of the Trash and lands on the desktop.
    private func clickUndo(at start: TimeInterval, file url: URL) {
        beat(start) {
            guard let button = self.stage.undoButtonPosition else { return }
            self.moveCursor(to: button, duration: 0.5)
        }
        beat(start + 0.6) {
            self.log.click()
            self.stage.showToast(title: "Back in play", subtitle: "\(url.lastPathComponent.middleTruncated(to: 26)) is out of the Trash", for: 2.5)
            self.scene.respawn(url)
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
        case .bank: bankTarget(on: basket)
        case .hoop: stage.hoop.map { CGPoint(x: $0.position.x, y: $0.position.y + 10) } ?? CGPoint(x: basket.position.x, y: rimY + 10)
        }
        return Self.launch(from: point, to: target, flight: flight)
    }

    /// A point on the inside face of the backboard, a little above the lip, for a file to bounce off.
    private func bankTarget(on basket: BasketNode) -> CGPoint {
        let side: CGFloat = basket.isBackboardOnRight ? 1 : -1
        let face = basket.reach - basket.side * 0.16
        return CGPoint(x: basket.position.x + side * (face - Throwable.radius + 2), y: basket.position.y + basket.rimHeight + Self.bankHeight)
    }

    /// How far above the opening a bank shot meets the board.
    private static let bankHeight: CGFloat = 70

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
        let frameCount = Int(cut.duration * Self.fps)
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
            if isHoldingBall { scene.dragBall(to: stage.cursor.position, time: now) }
            renderer.render(at: now, readBack: encoder != nil)
            trackBasket()
            if let encoder {
                renderer.pixels.withUnsafeBytes { encoder.pipe.fileHandleForWriting.write(Data($0)) }
                if frame % 120 == 0 { print("rendered \(frame / 60)s / \(Int(cut.duration))s") }
            }
            RunLoop.main.run(until: Date())
        }

        guard let output, let encoder else { return }
        try encoder.pipe.fileHandleForWriting.close()
        encoder.process.waitUntilExit()
        let soundtrack = FileManager.default.temporaryDirectory.appending(path: "hoop-promo-sound.wav")
        try log.writeSoundtrack(to: soundtrack, duration: cut.duration, music: cut == .funny ? nil : Music.render(duration: cut.duration))
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
