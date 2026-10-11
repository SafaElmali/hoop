import AppKit
import SpriteKit

/// The fake Mac desktop the promo plays out on, layered around the real game scene:
/// wallpaper, menu bar, Dock, desktop icons, cursor, captions, toasts, keycaps and menus.
final class Stage {
    static let size = CGSize(width: 1600, height: 900)
    static let menuBarHeight: CGFloat = 26

    private enum Layer {
        static let wallpaper: CGFloat = -100
        static let icons: CGFloat = -60
        static let menuBar: CGFloat = -55
        static let dock: CGFloat = -50
        static let dragImage: CGFloat = 40
        static let toast: CGFloat = 50
        static let caption: CGFloat = 60
        static let keycaps: CGFloat = 65
        static let menu: CGFloat = 70
        static let endCard: CGFloat = 80
        static let cursor: CGFloat = 100
    }

    let scene: CourtScene
    let cursor: SKSpriteNode
    private(set) var trashTile = CGRect.zero
    private(set) var statusIconPosition = CGPoint.zero
    private(set) var icons: [URL: DesktopIcon] = [:]
    /// Where Finder may put icons: below the menu bar, above the Dock.
    let desktopArea = CGRect(x: 0, y: 84, width: Stage.size.width, height: Stage.size.height - Stage.menuBarHeight - 84).insetBy(dx: 44, dy: 50)

    private let statusIcon = SKNode()
    private var caption: SKNode?
    private var toast: SKNode?
    private var restingToast: (title: String, subtitle: String)?
    private var menu: SKNode?
    private var menuRows: [SKShapeNode] = []
    private var dragImage: SKNode?

    var basket: BasketNode? { scene.children.first { $0 is BasketNode } as? BasketNode }

    init(scene: CourtScene) {
        self.scene = scene
        let arrow = NSCursor.arrow
        let image = arrow.image
        cursor = Props.image(image, side: max(image.size.width, image.size.height) * 1.6)
        cursor.anchorPoint = CGPoint(x: arrow.hotSpot.x / image.size.width, y: 1 - arrow.hotSpot.y / image.size.height)
        cursor.zPosition = Layer.cursor

        let wallpaper = Props.wallpaper(size: Self.size)
        wallpaper.zPosition = Layer.wallpaper
        scene.addChild(wallpaper)
        addMenuBar()
        addDock()
        scene.addChild(cursor)
    }

    // MARK: Desktop

    func place(_ url: URL, at point: CGPoint) {
        let icon = DesktopIcon(url: url)
        icon.position = point
        icon.zPosition = Layer.icons
        scene.addChild(icon)
        icons[url] = icon
    }

    /// The cursor picks up an icon: the original dims and a translucent copy follows the cursor.
    func pickUp(_ url: URL) {
        guard let icon = icons[url] else { return }
        icon.alpha = 0.45
        let image = DesktopIcon(url: url)
        image.alpha = 0.8
        image.position = CGPoint(x: icon.position.x - cursor.position.x, y: icon.position.y - cursor.position.y)
        image.zPosition = Layer.dragImage - Layer.cursor
        cursor.addChild(image)
        dragImage = image
    }

    /// Lets go of the dragged icon; returns where its centre was.
    func letGo() -> CGPoint {
        defer { dragImage?.removeFromParent(); dragImage = nil }
        guard let offset = dragImage?.position else { return cursor.position }
        return CGPoint(x: cursor.position.x + offset.x, y: cursor.position.y + offset.y)
    }

    /// Like Finder after a miss: the icon jumps to where the file landed, kept clear of the Dock and menu bar.
    func moveIcon(_ url: URL, to point: CGPoint) {
        guard let icon = icons[url] else { return }
        icon.alpha = 1
        icon.position = CGPoint(x: min(max(point.x, desktopArea.minX), desktopArea.maxX), y: min(max(point.y, desktopArea.minY), desktopArea.maxY))
    }

    func removeIcon(_ url: URL) {
        icons[url]?.removeFromParent()
        icons[url] = nil
    }

    func setShooting(_ shooting: Bool) {
        statusIcon.removeAllChildren()
        statusIcon.addChild(Props.symbol("basketball.fill", size: 15, color: shooting ? .systemOrange : .white))
    }

    // MARK: Overlays

    func showCaption(_ text: String) {
        caption?.removeFromParent()
        let label = Props.label(text, size: 44, weight: .heavy)
        let frame = label.frame
        let pill = Props.pill(size: CGSize(width: frame.width + 52, height: frame.height + 30), radius: 20, fill: NSColor(white: 0, alpha: 0.78))
        pill.addChild(label)
        label.zPosition = 0.1
        pill.position = CGPoint(x: Self.size.width / 2, y: Self.size.height - 175)
        pill.zPosition = Layer.caption
        pill.setScale(0.85)
        pill.alpha = 0
        let pop = SKAction.scale(to: 1, duration: 0.16)
        pop.timingMode = .easeOut
        pill.run(.group([pop, .fadeIn(withDuration: 0.1)]))
        scene.addChild(pill)
        caption = pill
    }

    func hideCaption() {
        caption?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        caption = nil
    }

    /// The app's top-of-screen message, drawn larger so it reads in a video.
    func showToast(title: String, subtitle: String, undo: Bool = false, for duration: TimeInterval? = nil) {
        toast?.removeFromParent()
        let scale: CGFloat = 1.35
        let ball = Props.symbol("basketball.fill", size: 20 * scale, color: .systemOrange)
        let titleLabel = Props.label(title, size: 13 * scale, weight: .semibold, color: NSColor(white: 0.08, alpha: 1))
        let subtitleLabel = Props.label(subtitle, size: 12 * scale, color: NSColor(white: 0.35, alpha: 1))
        for label in [titleLabel, subtitleLabel] { label.horizontalAlignmentMode = .left }
        let textWidth = max(titleLabel.frame.width, subtitleLabel.frame.width)
        var button: SKNode?
        if undo {
            let text = Props.label("Undo", size: 12 * scale, weight: .semibold)
            let shape = Props.pill(size: CGSize(width: text.frame.width + 22 * scale, height: 22 * scale), radius: 11 * scale, fill: .systemBlue)
            shape.addChild(text)
            text.zPosition = 0.1
            button = shape
        }
        let buttonWidth = button.map { $0.frame.width + 12 * scale } ?? 0
        let width = 14 * scale + ball.size.width + 12 * scale + textWidth + buttonWidth + (undo ? 10 : 18) * scale
        let height = 54 * scale
        let pill = Props.pill(size: CGSize(width: width, height: height), radius: height / 2, fill: NSColor(white: 0.97, alpha: 0.93), stroke: NSColor(white: 1, alpha: 0.6))
        var x = -width / 2 + 14 * scale
        ball.position = CGPoint(x: x + ball.size.width / 2, y: 0)
        x += ball.size.width + 12 * scale
        titleLabel.position = CGPoint(x: x, y: 9 * scale)
        subtitleLabel.position = CGPoint(x: x, y: -9 * scale)
        for node in [ball, titleLabel, subtitleLabel] as [SKNode] {
            node.zPosition = 0.1
            pill.addChild(node)
        }
        if let button {
            button.position = CGPoint(x: width / 2 - 10 * scale - button.frame.width / 2, y: 0)
            button.zPosition = 0.1
            pill.addChild(button)
        }
        pill.position = CGPoint(x: Self.size.width / 2, y: Self.size.height - Self.menuBarHeight - height / 2 - 6)
        pill.zPosition = Layer.toast
        scene.addChild(pill)
        toast = pill
        if let duration {
            pill.run(.sequence([.wait(forDuration: duration), .run { [weak self] in
                guard let self else { return }
                if let resting = restingToast { showToast(title: resting.title, subtitle: resting.subtitle) } else { pill.removeFromParent() }
            }]))
        } else {
            restingToast = (title, subtitle)
        }
    }

    func hideToast() {
        restingToast = nil
        toast?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        toast = nil
    }

    func showKeys(_ keys: [String]) {
        let group = SKNode()
        let side: CGFloat = 88
        for (index, key) in keys.enumerated() {
            let cap = Props.pill(size: CGSize(width: side, height: side), radius: 18, fill: NSColor(white: 0.97, alpha: 0.95), stroke: NSColor(white: 0.75, alpha: 1))
            let label = Props.label(key, size: 44, weight: .semibold, color: NSColor(white: 0.15, alpha: 1))
            label.zPosition = 0.1
            cap.addChild(label)
            cap.position = CGPoint(x: (CGFloat(index) - CGFloat(keys.count - 1) / 2) * (side + 18), y: 0)
            group.addChild(cap)
        }
        group.position = CGPoint(x: Self.size.width / 2, y: Self.size.height * 0.42)
        group.zPosition = Layer.keycaps
        group.setScale(0.7)
        let pop = SKAction.scale(to: 1, duration: 0.14)
        pop.timingMode = .easeOut
        group.run(.sequence([pop, .wait(forDuration: 1.1), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        scene.addChild(group)
    }

    /// A dropdown under the 🏀 status icon; returns the centre of each row.
    @discardableResult
    func showMenu(title: String, items: [String], selected: Int) -> [CGPoint] {
        hideMenu()
        let rowHeight: CGFloat = 34, width: CGFloat = 230
        let height = rowHeight * CGFloat(items.count + 1) + 12
        let panel = Props.pill(size: CGSize(width: width, height: height), radius: 10, fill: NSColor(white: 0.96, alpha: 0.96), stroke: NSColor(white: 0.7, alpha: 0.6))
        let origin = CGPoint(x: statusIconPosition.x + width / 2 - 24, y: statusIconPosition.y - 16 - height / 2)
        panel.position = origin
        panel.zPosition = Layer.menu
        let header = Props.label(title, size: 15, weight: .semibold, color: NSColor(white: 0.45, alpha: 1))
        header.horizontalAlignmentMode = .left
        header.position = CGPoint(x: -width / 2 + 16, y: height / 2 - 6 - rowHeight / 2)
        header.zPosition = 0.2
        panel.addChild(header)
        menuRows = []
        var centers: [CGPoint] = []
        for (index, item) in items.enumerated() {
            let y = height / 2 - 6 - rowHeight * CGFloat(index + 1) - rowHeight / 2
            let row = Props.pill(size: CGSize(width: width - 12, height: rowHeight - 4), radius: 6, fill: .clear)
            row.position = CGPoint(x: 0, y: y)
            row.zPosition = 0.1
            let check = Props.label(index == selected ? "✓" : "", size: 16, weight: .bold, color: NSColor(white: 0.1, alpha: 1))
            check.position = CGPoint(x: -width / 2 + 24, y: 0)
            let name = Props.label(item, size: 16, color: NSColor(white: 0.1, alpha: 1))
            name.horizontalAlignmentMode = .left
            name.position = CGPoint(x: -width / 2 + 40, y: 0)
            for node in [check, name] {
                node.zPosition = 0.1
                row.addChild(node)
            }
            panel.addChild(row)
            menuRows.append(row)
            centers.append(CGPoint(x: origin.x - 20, y: origin.y + y))
        }
        scene.addChild(panel)
        menu = panel
        return centers
    }

    func highlightMenuRow(_ index: Int) {
        for (rowIndex, row) in menuRows.enumerated() {
            let isOn = rowIndex == index
            row.fillColor = isOn ? .systemBlue : .clear
            for case let label as SKLabelNode in row.children {
                guard let text = label.attributedText?.string, !text.isEmpty else { continue }
                let font = label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 16)
                label.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: isOn ? NSColor.white : NSColor(white: 0.1, alpha: 1)])
            }
        }
    }

    func hideMenu() {
        menu?.removeFromParent()
        menu = nil
        menuRows = []
    }

    func showEndCard() {
        let card = SKNode()
        card.zPosition = Layer.endCard
        let shade = SKSpriteNode(color: NSColor(white: 0, alpha: 0.62), size: Self.size)
        shade.anchorPoint = .zero
        card.addChild(shade)
        let center = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        let icon = Props.appIcon(side: 210)
        icon.position = CGPoint(x: center.x, y: center.y + 150)
        let name = Props.label("Hoop", size: 112, weight: .heavy)
        name.position = CGPoint(x: center.x, y: center.y - 20)
        let tagline = Props.label("throw files into your Mac’s Trash 🏀", size: 40, weight: .semibold)
        tagline.position = CGPoint(x: center.x, y: center.y - 110)
        let footer = Props.label("free & open source · github.com/SafaElmali/hoop", size: 28, color: NSColor(white: 1, alpha: 0.75))
        footer.position = CGPoint(x: center.x, y: center.y - 175)
        for node in [icon, name, tagline, footer] as [SKNode] {
            node.zPosition = 0.1
            card.addChild(node)
        }
        card.alpha = 0
        card.run(.fadeIn(withDuration: 0.4))
        scene.addChild(card)
    }

    // MARK: Chrome

    private func addMenuBar() {
        let bar = SKSpriteNode(color: NSColor(white: 0, alpha: 0.22), size: CGSize(width: Self.size.width, height: Self.menuBarHeight))
        bar.anchorPoint = .zero
        bar.position = CGPoint(x: 0, y: Self.size.height - Self.menuBarHeight)
        bar.zPosition = Layer.menuBar
        scene.addChild(bar)
        let midY = Self.menuBarHeight / 2
        var x: CGFloat = 20
        for (index, title) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let label = Props.label(title, size: 14, weight: index == 0 ? .bold : .regular)
            label.horizontalAlignmentMode = .left
            label.position = CGPoint(x: x, y: midY)
            label.zPosition = 0.1
            bar.addChild(label)
            x += label.frame.width + 20
        }
        let clock = Props.label("Sun Oct 11  9:41 AM", size: 14)
        clock.horizontalAlignmentMode = .right
        clock.position = CGPoint(x: Self.size.width - 16, y: midY)
        clock.zPosition = 0.1
        bar.addChild(clock)
        var right = Self.size.width - 16 - clock.frame.width - 22
        for name in ["battery.75percent", "wifi"] {
            let symbol = Props.symbol(name, size: 14, color: .white)
            symbol.position = CGPoint(x: right - symbol.size.width / 2, y: midY)
            symbol.zPosition = 0.1
            bar.addChild(symbol)
            right -= symbol.size.width + 18
        }
        statusIcon.position = CGPoint(x: right - 8, y: midY)
        statusIcon.zPosition = 0.1
        bar.addChild(statusIcon)
        statusIconPosition = CGPoint(x: right - 8, y: Self.size.height - midY)
        setShooting(false)
    }

    private func addDock() {
        let appPaths = [
            "/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Messages.app",
            "/System/Applications/Mail.app", "/System/Applications/Maps.app", "/System/Applications/Photos.app",
            "/System/Applications/Notes.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app",
            "/System/Applications/App Store.app", "/System/Applications/System Settings.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        let tile: CGFloat = 54, gap: CGFloat = 6, padding: CGFloat = 10, separator: CGFloat = 16
        let width = CGFloat(appPaths.count + 1) * (tile + gap) - gap + separator + padding * 2
        let height = tile + padding * 2
        let dock = Props.pill(size: CGSize(width: width, height: height), radius: 22, fill: NSColor(white: 1, alpha: 0.2), stroke: NSColor(white: 1, alpha: 0.35))
        dock.position = CGPoint(x: Self.size.width / 2, y: 6 + height / 2)
        dock.zPosition = Layer.dock
        scene.addChild(dock)
        var x = -width / 2 + padding + tile / 2
        for path in appPaths {
            let icon = Props.image(NSWorkspace.shared.icon(forFile: path), side: tile)
            icon.position = CGPoint(x: x, y: 0)
            icon.zPosition = 0.1
            dock.addChild(icon)
            x += tile + gap
        }
        let line = SKSpriteNode(color: NSColor(white: 1, alpha: 0.35), size: CGSize(width: 1, height: tile - 8))
        line.position = CGPoint(x: x - gap / 2 + separator / 2 - tile / 2, y: 0)
        line.zPosition = 0.1
        dock.addChild(line)
        x += separator
        let trash = Props.image(NSImage(named: NSImage.trashEmptyName) ?? NSImage(), side: tile)
        trash.position = CGPoint(x: x, y: 0)
        trash.zPosition = 0.1
        dock.addChild(trash)
        trashTile = CGRect(x: dock.position.x + x - tile / 2, y: dock.position.y - tile / 2, width: tile, height: tile)
    }
}
