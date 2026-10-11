import AppKit
import Carbon.HIToolbox

/// Menu bar app. ⌃⌥H (or the 🏀 menu) toggles shoot mode: the Dock's Trash grows into a basket
/// and any file you drag gets thrown when you let go. Esc leaves shoot mode. 🏀 → Shot Clock starts
/// a 30-second round with paper balls to throw.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    /// Where the basket lives: on the Dock's Trash tile, or wherever the player dragged it.
    private struct Spot {
        /// The bottom of the can, in screen coordinates.
        let home: CGPoint
        /// The Trash tile in the Dock; nil once the basket has been dragged off it, or on a screen without the Dock.
        let dockTile: CGRect?
        let screen: NSScreen
    }

    private static let denials = ["Denied!", "Not today", "Too slow", "Nope"]

    private let trashCan = TrashCan()
    private let sounds = Sounds()
    private let toast = Toast()
    private let scorekeeper = Scorekeeper()
    private let folderHoopMenu = NSMenu()
    private var scene: CourtScene!
    private var overlay: OverlayWindow!
    private var statusItem: NSStatusItem!
    private var toggleKey: HotKey?
    private var escapeKey: HotKey?
    private var dockWatcher: Timer?
    private var spot: Spot?
    /// The Shot Clock round under way, if any.
    private var shotClock: ShotClock?

    /// Recording lets go of the current shortcut, so typing it records it instead of toggling shoot
    /// mode; shoot mode stops too, so Esc cancels the recording instead of leaving shoot mode.
    private lazy var shortcutWindow = ShortcutWindow { [unowned self] shortcut in
        if let shortcut {
            registerShortcut(shortcut)
        } else {
            toggleKey = nil
            if isShooting { stopShooting() }
        }
    }

    private var isShooting: Bool { escapeKey != nil }
    private var screen: NSScreen { spot?.screen ?? NSScreen.main ?? NSScreen.screens[0] }

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .normal }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "mode")
            scene.mode = newValue
        }
    }

    private var basketSize: BasketSize {
        get { BasketSize(rawValue: UserDefaults.standard.string(forKey: "basketSize") ?? "") ?? .medium }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "basketSize")
            scene.basketSize = newValue
        }
    }

    /// The glass backboard on the grown Trash.
    private var hasBackboard: Bool {
        get { UserDefaults.standard.bool(forKey: "backboard") }
        set {
            UserDefaults.standard.set(newValue, forKey: "backboard")
            scene.hasBackboard = newValue
        }
    }

    /// Where files thrown through the folder hoop go; nil when the hoop is off.
    private var hoopFolder: URL? {
        get { UserDefaults.standard.string(forKey: "hoopFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "hoopFolder") }
    }

    /// Where the player last dropped the basket (bottom of the can, screen coordinates).
    private var savedHome: CGPoint? {
        get { UserDefaults.standard.point(forKey: "basketHome") }
        set { UserDefaults.standard.setPoint(newValue, forKey: "basketHome") }
    }

    /// Where the player last dropped the folder hoop (middle of its rim, screen coordinates).
    private var savedHoopCenter: CGPoint? {
        get { UserDefaults.standard.point(forKey: "hoopHome") }
        set { UserDefaults.standard.setPoint(newValue, forKey: "hoopHome") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        scene = CourtScene(sounds: sounds)
        scene.mode = mode
        scene.basketSize = basketSize
        scene.hasBackboard = hasBackboard
        scene.onScore = { [unowned self] url, make in
            switch make.target {
            case .trash: trash(url, make: make)
            case let .folder(folder): move(url, into: folder, make: make)
            }
        }
        scene.onLand = { [unowned self] url, point, wasThrown in
            landed(url, at: overlay.screenPoint(fromScene: point), wasThrown: wasThrown)
        }
        scene.onPracticeScore = { [unowned self] make in practiceMade(make) }
        scene.onPracticeMiss = { [unowned self] in practiceMissed() }
        scene.onBasketMoved = { [unowned self] point in
            savedHome = overlay.screenPoint(fromScene: point)
            spot = locateBasket(on: screen)
        }
        scene.onHoopMoved = { [unowned self] point in
            savedHoopCenter = overlay.screenPoint(fromScene: point)
        }
        overlay = OverlayWindow(scene: scene)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "basketball.fill", accessibilityDescription: "Hoop")
        statusItem.menu = makeMenu()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.followTrash()
        }

        if !DockTrash.isTrusted { DockTrash.requestAccess() }
        toast.show(ToastContent(title: "Hoop is ready", subtitle: "Press \(Shortcut.saved.symbols), or use 🏀 in the menu bar, to start shooting"), on: screen, for: 5)
        // After the welcome, so a shortcut that can't be registered gets the last word.
        registerShortcut()
    }

    // MARK: Shoot mode

    @objc func toggleShootMode(_ sender: Any?) {
        isShooting ? stopShooting() : startShooting()
    }

    private func startShooting() {
        let spot = locateBasket(on: .underPointer)
        self.spot = spot
        Log.event("shoot mode on: accessibility=\(DockTrash.isTrusted) dockTile=\(spot.dockTile.map { "\($0)" } ?? "none") home=\(spot.home) screen=\(spot.screen.frame)")
        overlay.show(on: spot.screen, home: spot.home, dockTile: spot.dockTile)
        mountHoop()
        escapeKey = HotKey(keyCode: kVK_Escape, modifiers: 0) { [unowned self] in stopShooting() }
        statusItem.button?.contentTintColor = .systemOrange
        showHint()
        // The Dock can resize or move; keep the basket on the Trash.
        dockWatcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.followTrash() }
    }

    private func stopShooting() {
        escapeKey = nil
        dockWatcher?.invalidate()
        // A Shot Clock round ends with shoot mode; hiding the overlay clears away its paper balls.
        shotClock?.cancel()
        shotClock = nil
        overlay.hide()
        statusItem.button?.contentTintColor = nil
        toast.clearResting()
    }

    /// The toast shoot mode rests on: the clock during a Shot Clock round, else a hint for the mode.
    private func showHint() {
        if let shotClock { return toast.rest(shotClock.hud, on: screen) }
        let hint: String
        if spot?.dockTile != nil, !DockTrash.isTrusted {
            hint = "Allow Accessibility in the 🏀 menu so Hoop can find your Trash"
        } else {
            switch mode {
            case .normal: hint = "Throw files into the Trash · drag the Trash to move it · esc to stop"
            case .moving: hint = "The Trash is on the move · esc to stop"
            case .impossible: hint = "Good luck · esc to stop"
            }
        }
        toast.rest(ToastContent(title: "Shoot mode · \(mode.title)", subtitle: hint), on: screen)
    }

    /// Keeps the basket on the Trash as the Dock resizes or moves, including onto or off this screen,
    /// and starts over if the screen goes away or changes. A basket the player dragged stays put.
    private func followTrash() {
        // Skip while dragging.
        guard isShooting, !overlay.isArmed, let current = spot else { return }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == current.screen.displayID }), screen.frame == overlay.frame else {
            stopShooting()
            return startShooting()
        }
        guard current.dockTile != nil || current.home != savedHome else { return }
        let latest = locateBasket(on: screen)
        // Skip while the pointer is over the Dock, where magnification shifts icons.
        let pointer = NSEvent.mouseLocation
        if let tile = latest.dockTile, latest.screen.frame.contains(pointer), pointer.y <= tile.maxY + 40 { return }
        if latest.screen.displayID != screen.displayID {
            // The Dock-sized Trash follows the Dock to another screen.
            stopShooting()
            startShooting()
        } else if latest.home != current.home || latest.dockTile != current.dockTile {
            spot = latest
            // Growing out of the Dock, or back into it, is worth seeing; a nudge along the Dock isn't.
            overlay.moveBasket(home: latest.home, dockTile: latest.dockTile, animated: (latest.dockTile == nil) != (current.dockTile == nil))
        }
    }

    /// Where the basket goes on `screen`: the spot the player dragged it to if that's on this screen,
    /// else the Trash tile if the Dock is here, else the bottom centre of the screen.
    /// The Dock-sized Trash always sits in the Dock, on the Dock's screen.
    private func locateBasket(on screen: NSScreen) -> Spot {
        if basketSize != .dock, let home = savedHome, screen.frame.contains(home) {
            return Spot(home: home, dockTile: nil, screen: screen)
        }
        let trash = locateTrash()
        if basketSize == .dock || trash.screen.displayID == screen.displayID {
            return Spot(home: BasketNode.base(onDockTile: trash.frame), dockTile: trash.frame, screen: trash.screen)
        }
        return Spot(home: CGPoint(x: screen.frame.midX, y: screen.frame.minY + 10), dockTile: nil, screen: screen)
    }

    /// The Trash tile from the Dock, or a best guess (bottom-right) without Accessibility access.
    private func locateTrash() -> (frame: CGRect, screen: NSScreen) {
        if var frame = DockTrash.frame(),
           let screen = NSScreen.screens.first(where: { $0.frame.minX <= frame.midX && frame.midX < $0.frame.maxX }) {
            // An auto-hidden Dock reports its icons off screen.
            frame.origin.y = min(max(frame.minY, screen.frame.minY + 4), screen.frame.maxY - frame.height)
            return (frame, screen)
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return (CGRect(x: screen.frame.maxX - 140, y: screen.frame.minY + 6, width: 64, height: 64), screen)
    }

    /// Puts up the folder hoop on the shoot mode screen: where the player dragged it if that's on
    /// this screen, else at the bottom left, across from where the Trash usually sits. Takes it down
    /// when the folder hoop is off.
    private func mountHoop() {
        let area = screen.visibleFrame
        var center = CGPoint(x: area.minX + area.width * 0.2, y: area.minY + area.height * 0.28)
        if let saved = savedHoopCenter, screen.frame.contains(saved) { center = saved }
        overlay.mountHoop(folder: hoopFolder, rimCenter: center, animated: true)
    }

    // MARK: Shot Clock

    /// Starts a round, turning shoot mode on first if it's off, or calls off the round under way.
    @objc func toggleShotClock(_ sender: Any?) {
        shotClock == nil ? startShotClock() : callOffShotClock()
    }

    /// A whistle, a rack of paper balls across from the Trash, and the clock running.
    private func startShotClock() {
        if !isShooting { startShooting() }
        let clock = ShotClock { [unowned self] clock in clockTicked(clock) }
        shotClock = clock
        mountRack()
        sounds.play(.whistle)
        showHint()
        clock.start()
    }

    /// Ends the round before the buzzer, with no result; shoot mode carries on.
    private func callOffShotClock() {
        shotClock?.cancel()
        shotClock = nil
        scene.clearPractice()
        showHint()
    }

    /// The last five seconds tick. At zero: the buzzer, the balls cleared away, and the result over
    /// shoot mode's usual hint.
    private func clockTicked(_ clock: ShotClock) {
        guard clock.isOver else {
            if clock.secondsLeft <= 5 { sounds.play(.tick) }
            return updateClock()
        }
        sounds.play(.buzzer)
        shotClock = nil
        scene.clearPractice()
        showHint()
        toast.show(clock.result, on: screen, for: 5)
    }

    /// Puts the clock and score in the resting toast, without cutting a callout short.
    private func updateClock() {
        guard let shotClock else { return }
        toast.updateResting(shotClock.hud, on: screen)
    }

    /// Stands the paper ball rack at the bottom of the screen, on the side away from the Trash.
    private func mountRack() {
        let area = screen.visibleFrame
        let isTrashOnRight = (spot?.home.x ?? area.maxX) > area.midX
        overlay.mountRack(center: CGPoint(x: isTrashOnRight ? area.minX + 150 : area.maxX - 150, y: area.minY + 12))
    }

    /// A paper ball went in: it counts for the round and the streak, but stays out of Stats.
    private func practiceMade(_ make: MakeInfo) {
        let callout = scorekeeper.recordMake(make, bytes: 0, isPractice: true)
        scene.isOnFire = scorekeeper.isOnFire
        shotClock?.recordMake()
        // Paper into the bin: the crumple a file makes going into the Trash.
        if make.target == .trash { sounds.play(.trash) }
        sounds.play(.make)
        let made = shotClock.map { "\($0.made) made" }
        toast.show(ToastContent(title: callout.title, subtitle: [made, callout.note].compactMap { $0 }.joined(separator: " · ")), on: screen, for: 2)
        updateClock()
    }

    /// A paper ball missed: the streak ends, and only a fire going out is worth a word.
    private func practiceMissed() {
        let callout = scorekeeper.recordMiss(isPractice: true)
        scene.isOnFire = scorekeeper.isOnFire
        guard let callout, let shotClock else { return }
        toast.show(ToastContent(title: callout.title, subtitle: "\(shotClock.made) made"), on: screen, for: 2)
    }

    // MARK: Files

    private func trash(_ url: URL, make: MakeInfo) {
        let name = url.lastPathComponent.middleTruncated(to: 28)
        let bytes = Scorekeeper.size(of: url) // while it's still where it was
        trashCan.trash(url) { [weak self] result in
            guard let self else { return }
            Log.event("trash \(url.lastPathComponent): \(result)")
            switch result {
            case let .success(trashed):
                // Finder plays its own trash sound; moving the file ourselves is silent.
                if !trashed.byFinder { sounds.play(.trash) }
                celebrate(make, of: name, into: "Trash", bytes: bytes, undoable: trashed.undoable)
            case let .failure(error):
                toast.show(ToastContent(title: "Couldn’t trash \(name)", subtitle: error.localizedDescription), on: screen, for: 4)
                scene.respawn(url)
            }
        }
    }

    /// A file went through the folder hoop: it moves into the hoop's folder.
    private func move(_ url: URL, into folder: URL, make: MakeInfo) {
        let name = url.lastPathComponent.middleTruncated(to: 28)
        do {
            let moved = try trashCan.move(url, into: folder)
            Log.event("move \(url.lastPathComponent) into \(folder.path): moved=\(moved)")
            celebrate(make, of: name, into: folder.displayName, bytes: 0, undoable: moved)
        } catch {
            Log.event("move \(url.lastPathComponent) into \(folder.path): \(error)")
            toast.show(ToastContent(title: "Couldn’t move \(name)", subtitle: error.localizedDescription), on: screen, for: 4)
            scene.respawn(url, from: make.target)
        }
    }

    /// Counts a make (for the Shot Clock round too, when one's on) and shows its callout,
    /// "name → destination", with Undo when it can be undone. `bytes` is how much it trashed.
    private func celebrate(_ make: MakeInfo, of name: String, into destination: String, bytes: Int, undoable: Bool) {
        let callout = scorekeeper.recordMake(make, bytes: bytes)
        scene.isOnFire = scorekeeper.isOnFire
        shotClock?.recordMake()
        sounds.play(.make)
        let undo = undoable ? ToastAction(title: "Undo") { [weak self] in self?.undoShot(nil) } : nil
        let subtitle = ["\(name) → \(destination)", callout.note].compactMap { $0 }.joined(separator: " · ")
        toast.show(ToastContent(title: callout.title, subtitle: subtitle, action: undo), on: screen, for: 6)
        updateClock()
    }

    /// A file came to rest outside the goals. A desktop file's real icon moves to where it landed
    /// (kept clear of the Dock and menu bar); files from other folders stay in their folder.
    private func landed(_ url: URL, at point: CGPoint, wasThrown: Bool) {
        Log.event("landed \(url.lastPathComponent) at \(point)")
        let onDesktop = Finder.isOnDesktop(url)
        if onDesktop {
            let area = screen.visibleFrame.insetBy(dx: 44, dy: 50)
            Finder.moveDesktopIcon(of: url, to: CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY)))
        }
        guard wasThrown else { return }
        let callout = scorekeeper.recordMiss()
        scene.isOnFire = scorekeeper.isOnFire
        let name = url.lastPathComponent.middleTruncated(to: 28)
        var message = mode == .impossible
            ? ToastContent(title: Self.denials.randomElement()!, subtitle: "Impossible mode never lets one in")
            : ToastContent(title: "Brick!", subtitle: onDesktop ? "\(name) stays where it landed" : "\(name) stays in its folder")
        if let callout { message.title = callout.title }
        toast.show(message, on: screen, for: 2)
    }

    @objc func undoShot(_ sender: Any?) {
        do {
            let (restored, target) = try trashCan.undo()
            if isShooting { scene.respawn(restored, from: target) }
            let place = switch target {
            case .trash: "the Trash"
            case let .folder(folder): folder.displayName
            }
            toast.show(ToastContent(title: "Back in play", subtitle: "\(restored.lastPathComponent.middleTruncated(to: 28)) is out of \(place)"), on: screen, for: 3)
        } catch {
            toast.show(ToastContent(title: "Couldn’t undo", subtitle: error.localizedDescription), on: screen, for: 4)
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // Its key equivalent shows the current shortcut; see validateMenuItem.
        menu.addItem(item("Shoot Mode", #selector(toggleShootMode(_:))))
        menu.addItem(item("Shot Clock", #selector(toggleShotClock(_:))))

        let modes = NSMenu()
        for mode in Mode.allCases {
            let choice = item(mode.title, #selector(chooseMode(_:)))
            choice.representedObject = mode.rawValue
            modes.addItem(choice)
        }
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(modeItem)

        let sizes = NSMenu()
        for size in BasketSize.allCases {
            let choice = item(size.title, #selector(chooseSize(_:)))
            choice.representedObject = size.rawValue
            sizes.addItem(choice)
        }
        let sizeItem = NSMenuItem(title: "Trash Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(item("Backboard", #selector(toggleBackboard(_:))))
        folderHoopMenu.delegate = self
        let folderHoopItem = NSMenuItem(title: "Folder Hoop", action: nil, keyEquivalent: "")
        folderHoopItem.submenu = folderHoopMenu
        menu.addItem(folderHoopItem)
        menu.addItem(item("Put Trash Back on Dock", #selector(putTrashBack(_:))))
        menu.addItem(item("Undo", #selector(undoShot(_:))))
        menu.addItem(.separator())

        let stats = NSMenu()
        stats.delegate = self
        menuNeedsUpdate(stats)
        let statsItem = NSMenuItem(title: "Stats", action: nil, keyEquivalent: "")
        statsItem.submenu = stats
        menu.addItem(statsItem)
        let packs = NSMenu()
        for pack in SoundPack.allCases {
            if pack == .off { packs.addItem(.separator()) }
            let choice = item(pack.title, #selector(chooseSoundPack(_:)))
            choice.representedObject = pack.rawValue
            packs.addItem(choice)
        }
        let soundsItem = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        soundsItem.submenu = packs
        menu.addItem(soundsItem)
        menu.addItem(item("Shortcut…", #selector(showShortcutWindow(_:))))
        menu.addItem(item("Open at Login", #selector(toggleOpenAtLogin(_:))))
        menu.addItem(item("Allow Accessibility…", #selector(openAccessibilitySettings(_:))))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hoop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleShootMode(_:)):
            menuItem.state = isShooting ? .on : .off
            let shortcut = Shortcut.saved
            menuItem.keyEquivalent = shortcut.keyEquivalent
            menuItem.keyEquivalentModifierMask = shortcut.modifierFlags
            return true
        case #selector(toggleShotClock(_:)):
            menuItem.state = shotClock != nil ? .on : .off
            return true
        case #selector(chooseMode(_:)):
            menuItem.state = menuItem.representedObject as? String == mode.rawValue ? .on : .off
            return true
        case #selector(chooseSize(_:)):
            menuItem.state = menuItem.representedObject as? String == basketSize.rawValue ? .on : .off
            return true
        case #selector(toggleBackboard(_:)):
            menuItem.state = hasBackboard ? .on : .off
            // The Dock-sized Trash never gets one.
            return basketSize != .dock
        case #selector(chooseHoopFolder(_:)):
            // Off has no folder, so it's checked while the hoop is off.
            menuItem.state = (menuItem.representedObject as? URL)?.path == hoopFolder?.path ? .on : .off
            return true
        case #selector(putTrashBack(_:)):
            return savedHome != nil && basketSize != .dock
        case #selector(undoShot(_:)):
            menuItem.title = trashCan.lastShot.map { "Undo “\($0.original.lastPathComponent.middleTruncated(to: 28))”" } ?? "Undo"
            return trashCan.lastShot != nil
        case #selector(chooseSoundPack(_:)):
            menuItem.state = menuItem.representedObject as? String == sounds.pack.rawValue ? .on : .off
            return true
        case #selector(toggleOpenAtLogin(_:)):
            menuItem.state = LoginItem.isEnabled ? .on : .off
            return true
        case #selector(openAccessibilitySettings(_:)):
            menuItem.isHidden = DockTrash.isTrusted
            return true
        default:
            return true
        }
    }

    /// Refills the Stats submenu with the latest numbers each time it opens, and the Folder Hoop one
    /// with the chosen folder.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu !== folderHoopMenu else { return fillFolderHoopMenu() }
        let makes = scorekeeper.makes, misses = scorekeeper.misses
        var shooting = "Makes \(makes) · Misses \(misses)"
        if makes + misses > 0 { shooting += " · \(Int((Double(makes) * 100 / Double(makes + misses)).rounded()))%" }
        let bytes = ByteCountFormatter()
        bytes.allowsNonnumericFormatting = false
        menu.removeAllItems()
        // No action, so they show as plain disabled rows.
        for row in [shooting, "Best streak \(scorekeeper.bestStreak)", "Trashed \(bytes.string(fromByteCount: Int64(scorekeeper.bytesTrashed)))"] {
            menu.addItem(withTitle: row, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(item("Reset Stats", #selector(resetStats(_:))))
    }

    /// Off, the usual folders, the chosen folder if it's another one, and Choose Folder….
    private func fillFolderHoopMenu() {
        var folders = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory]
            .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
        if let hoopFolder, !folders.contains(where: { $0.path == hoopFolder.path }) { folders.append(hoopFolder) }
        folderHoopMenu.removeAllItems()
        folderHoopMenu.addItem(item("Off", #selector(chooseHoopFolder(_:))))
        folderHoopMenu.addItem(.separator())
        for folder in folders {
            let choice = item(folder.displayName, #selector(chooseHoopFolder(_:)))
            choice.representedObject = folder
            folderHoopMenu.addItem(choice)
        }
        folderHoopMenu.addItem(.separator())
        folderHoopMenu.addItem(item("Choose Folder…", #selector(pickHoopFolder(_:))))
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        self.mode = mode
        if isShooting { showHint() }
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = BasketSize(rawValue: raw) else { return }
        let wasDock = basketSize == .dock
        basketSize = size
        // Going to or from Dock Size moves the Trash between the Dock and wherever it was dragged.
        guard isShooting, wasDock != (size == .dock) else { return }
        let spot = locateBasket(on: screen)
        guard spot.screen.displayID == screen.displayID else {
            // The Dock-sized Trash lives on the Dock's screen.
            stopShooting()
            return startShooting()
        }
        self.spot = spot
        overlay.moveBasket(home: spot.home, dockTile: spot.dockTile, animated: true)
    }

    @objc private func toggleBackboard(_ sender: Any?) {
        hasBackboard.toggle()
    }

    @objc private func chooseHoopFolder(_ sender: NSMenuItem) {
        useHoopFolder(sender.representedObject as? URL)
    }

    @objc private func pickHoopFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Files you throw through the folder hoop move into this folder"
        panel.directoryURL = hoopFolder
        // Hoop has no Dock icon or app menu, so bring the app forward along with the panel.
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            self?.useHoopFolder(folder)
        }
    }

    private func useHoopFolder(_ folder: URL?) {
        hoopFolder = folder
        if isShooting { mountHoop() }
    }

    @objc private func putTrashBack(_ sender: Any?) {
        savedHome = nil
        spot = locateBasket(on: screen)
        guard isShooting, let spot else { return }
        overlay.moveBasket(home: spot.home, dockTile: spot.dockTile, animated: true)
    }

    @objc private func resetStats(_ sender: Any?) {
        scorekeeper.reset()
        scene.isOnFire = false
    }

    @objc private func chooseSoundPack(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pack = SoundPack(rawValue: raw) else { return }
        sounds.pack = pack
        sounds.preview()
    }

    @objc private func showShortcutWindow(_ sender: Any?) {
        shortcutWindow.show()
    }

    /// Registers the shoot mode shortcut, letting go of the old one first in case it's the same keys.
    private func registerShortcut(_ shortcut: Shortcut = .saved) {
        toggleKey = nil
        toggleKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [unowned self] in toggleShootMode(nil) }
        guard toggleKey?.isRegistered == false else { return }
        toast.show(ToastContent(title: "Couldn’t use \(shortcut.symbols)", subtitle: "Something else has it · pick another in 🏀 → Shortcut…"), on: screen, for: 5)
    }

    @objc private func toggleOpenAtLogin(_ sender: Any?) {
        do {
            try LoginItem.toggle()
        } catch {
            toast.show(ToastContent(title: "Couldn’t change Open at Login", subtitle: error.localizedDescription), on: screen, for: 4)
        }
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        DockTrash.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
