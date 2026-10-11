import AppKit
import Carbon.HIToolbox

/// Menu bar app. ⌃⌥H (or the 🏀 menu) toggles shoot mode: the Dock's Trash grows into a basket
/// and any file you drag gets thrown when you let go. Esc leaves shoot mode.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Where the basket lives: on the Dock's Trash tile, or wherever the player dragged it.
    private struct Spot {
        /// The bottom of the can, in screen coordinates.
        let home: CGPoint
        /// The Trash tile in the Dock; nil once the basket has been dragged off it.
        let dockTile: CGRect?
        let screen: NSScreen
    }

    private static let denials = ["Denied!", "Not today", "Too slow", "Nope"]

    private let trashCan = TrashCan()
    private let sounds = Sounds()
    private let toast = Toast()
    private var scene: CourtScene!
    private var overlay: OverlayWindow!
    private var statusItem: NSStatusItem!
    private var toggleKey: HotKey?
    private var escapeKey: HotKey?
    private var dockWatcher: Timer?
    private var spot: Spot?

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

    /// Where the player last dropped the basket (bottom of the can, screen coordinates).
    private var savedHome: CGPoint? {
        get {
            guard let xy = UserDefaults.standard.array(forKey: "basketHome") as? [Double], xy.count == 2 else { return nil }
            return CGPoint(x: xy[0], y: xy[1])
        }
        set { UserDefaults.standard.set(newValue.map { [Double($0.x), Double($0.y)] }, forKey: "basketHome") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        scene = CourtScene(sounds: sounds)
        scene.mode = mode
        scene.basketSize = basketSize
        scene.onScore = { [unowned self] url in trash(url) }
        scene.onLand = { [unowned self] url, point, wasThrown in
            landed(url, at: overlay.screenPoint(fromScene: point), wasThrown: wasThrown)
        }
        scene.onBasketMoved = { [unowned self] point in
            savedHome = overlay.screenPoint(fromScene: point)
            spot = locateBasket()
        }
        overlay = OverlayWindow(scene: scene)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "basketball.fill", accessibilityDescription: "Hoop")
        statusItem.menu = makeMenu()

        toggleKey = HotKey(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey) { [unowned self] in toggleShootMode(nil) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.followTrash()
        }

        if !DockTrash.isTrusted { DockTrash.requestAccess() }
        toast.show(ToastContent(title: "Hoop is ready", subtitle: "Press ⌃⌥H, or use 🏀 in the menu bar, to start shooting"), on: screen, for: 5)
    }

    // MARK: Shoot mode

    @objc func toggleShootMode(_ sender: Any?) {
        isShooting ? stopShooting() : startShooting()
    }

    private func startShooting() {
        let spot = locateBasket()
        self.spot = spot
        Log.event("shoot mode on: accessibility=\(DockTrash.isTrusted) dockTile=\(spot.dockTile.map { "\($0)" } ?? "none") home=\(spot.home) screen=\(spot.screen.frame)")
        overlay.show(on: spot.screen, home: spot.home, dockTile: spot.dockTile)
        escapeKey = HotKey(keyCode: kVK_Escape, modifiers: 0) { [unowned self] in stopShooting() }
        statusItem.button?.contentTintColor = .systemOrange
        showHint()
        // The Dock can resize or move; keep the basket on the Trash.
        dockWatcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.followTrash() }
    }

    private func stopShooting() {
        escapeKey = nil
        dockWatcher?.invalidate()
        overlay.hide()
        statusItem.button?.contentTintColor = nil
        toast.clearResting()
    }

    private func showHint() {
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

    private func followTrash() {
        // Only while the basket sits on the Dock. Skip while dragging, and while the pointer is over
        // the Dock, where magnification shifts icons.
        guard isShooting, !overlay.isArmed, let current = spot, let tile = current.dockTile else { return }
        let pointer = NSEvent.mouseLocation
        guard pointer.y > tile.maxY + 40 || !current.screen.frame.contains(pointer) else { return }
        let latest = locateBasket()
        if latest.screen != current.screen {
            stopShooting()
            startShooting()
        } else if latest.dockTile != tile {
            spot = latest
            overlay.moveBasket(home: latest.home, dockTile: latest.dockTile, animated: false)
        }
    }

    /// The spot the player dragged the basket to, else the Trash tile in the Dock.
    /// The Dock-sized Trash always sits in the Dock.
    private func locateBasket() -> Spot {
        if basketSize != .dock, let home = savedHome, let screen = NSScreen.screens.first(where: { $0.frame.contains(home) }) {
            return Spot(home: home, dockTile: nil, screen: screen)
        }
        let (tile, screen) = locateTrash()
        return Spot(home: BasketNode.base(onDockTile: tile), dockTile: tile, screen: screen)
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

    // MARK: Files

    private func trash(_ url: URL) {
        let name = url.lastPathComponent.middleTruncated(to: 28)
        trashCan.trash(url) { [weak self] result in
            guard let self else { return }
            Log.event("trash \(url.lastPathComponent): \(result)")
            switch result {
            case let .success(trashed):
                // Finder plays its own trash sound; moving the file ourselves is silent.
                if !trashed.byFinder { sounds.play(.trash) }
                let undo = trashed.undoable ? ToastAction(title: "Undo") { [weak self] in self?.undoShot(nil) } : nil
                toast.show(ToastContent(title: CourtScene.randomCheer(), subtitle: "\(name) → Trash", action: undo), on: screen, for: 6)
            case let .failure(error):
                toast.show(ToastContent(title: "Couldn’t trash \(name)", subtitle: error.localizedDescription), on: screen, for: 4)
                scene.respawn(url)
            }
        }
    }

    /// A file came to rest outside the Trash. A desktop file's real icon moves to where it landed
    /// (kept clear of the Dock and menu bar); files from other folders stay in their folder.
    private func landed(_ url: URL, at point: CGPoint, wasThrown: Bool) {
        Log.event("landed \(url.lastPathComponent) at \(point)")
        let onDesktop = Finder.isOnDesktop(url)
        if onDesktop {
            let area = screen.visibleFrame.insetBy(dx: 44, dy: 50)
            Finder.moveDesktopIcon(of: url, to: CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY)))
        }
        guard wasThrown else { return }
        let name = url.lastPathComponent.middleTruncated(to: 28)
        let message = mode == .impossible
            ? ToastContent(title: Self.denials.randomElement()!, subtitle: "Impossible mode never lets one in")
            : ToastContent(title: "Brick!", subtitle: onDesktop ? "\(name) stays where it landed" : "\(name) stays in its folder")
        toast.show(message, on: screen, for: 2)
    }

    @objc func undoShot(_ sender: Any?) {
        do {
            let restored = try trashCan.undo()
            if isShooting { scene.respawn(restored) }
            toast.show(ToastContent(title: "Back in play", subtitle: "\(restored.lastPathComponent.middleTruncated(to: 28)) is out of the Trash"), on: screen, for: 3)
        } catch {
            toast.show(ToastContent(title: "Couldn’t undo", subtitle: error.localizedDescription), on: screen, for: 4)
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let shoot = item("Shoot Mode", #selector(toggleShootMode(_:)), key: "h")
        shoot.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(shoot)

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
        menu.addItem(item("Put Trash Back on Dock", #selector(putTrashBack(_:))))
        menu.addItem(item("Undo", #selector(undoShot(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Sound Effects", #selector(toggleSound(_:))))
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
            return true
        case #selector(chooseMode(_:)):
            menuItem.state = menuItem.representedObject as? String == mode.rawValue ? .on : .off
            return true
        case #selector(chooseSize(_:)):
            menuItem.state = menuItem.representedObject as? String == basketSize.rawValue ? .on : .off
            return true
        case #selector(putTrashBack(_:)):
            return savedHome != nil && basketSize != .dock
        case #selector(undoShot(_:)):
            menuItem.title = trashCan.lastShot.map { "Undo “\($0.original.lastPathComponent.middleTruncated(to: 28))”" } ?? "Undo"
            return trashCan.lastShot != nil
        case #selector(toggleSound(_:)):
            menuItem.state = sounds.isEnabled ? .on : .off
            return true
        case #selector(openAccessibilitySettings(_:)):
            menuItem.isHidden = DockTrash.isTrusted
            return true
        default:
            return true
        }
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
        let spot = locateBasket()
        self.spot = spot
        overlay.moveBasket(home: spot.home, dockTile: spot.dockTile, animated: true)
    }

    @objc private func putTrashBack(_ sender: Any?) {
        savedHome = nil
        spot = locateBasket()
        guard isShooting, let spot else { return }
        overlay.moveBasket(home: spot.home, dockTile: spot.dockTile, animated: true)
    }

    @objc private func toggleSound(_ sender: Any?) {
        sounds.isEnabled.toggle()
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        DockTrash.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
