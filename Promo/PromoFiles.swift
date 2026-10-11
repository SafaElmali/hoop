import AppKit

/// Real (throwaway) files for the fake desktop, so icons and previews look like the real thing.
struct PromoFiles {
    let screenshot: URL
    let psd: URL
    let resume: URL
    let photo: URL
    let taxes: URL
    let clutter: [URL]

    init() throws {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appending(path: "hoop-promo-desktop", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        func file(_ name: String) -> URL { folder.appending(path: name) }

        screenshot = file("Screenshot 2026-10-11 at 09.41.12.png")
        psd = file("final_FINAL_v3_REAL.psd")
        resume = file("resume_old_old.docx")
        photo = file("IMG_4821.jpg")
        taxes = file("taxes_2019.pdf")
        let moreScreenshots = [file("Screenshot 2026-10-11 at 09.42.03.png"), file("Screenshot 2026-10-11 at 09.43.27.png")]
        let folders = [file("untitled folder 7"), file("node_modules copy")]
        let todo = file("todo (2).txt")
        clutter = folders + moreScreenshots + [todo, file("new new logo.png")]

        try Self.screenshot(accent: NSColor(hex: 0x4A5AEF)).write(to: screenshot)
        for (index, url) in moreScreenshots.enumerated() {
            try Self.screenshot(accent: index == 0 ? NSColor(hex: 0x22A06B) : NSColor(hex: 0xE5484D)).write(to: url)
        }
        try Self.logo().write(to: clutter.last!)
        try Self.sunset().write(to: photo)
        try Self.taxReturn(to: taxes)
        try Data().write(to: psd)
        try Data().write(to: resume)
        try "- clean desktop\n- do taxes (2019)\n- do taxes (2020)".write(to: todo, atomically: true, encoding: .utf8)
        for url in folders { try fileManager.createDirectory(at: url, withIntermediateDirectories: true) }
    }

    private static func bitmap(width: Int, height: Int, draw: (CGSize) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(CGSize(width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// A window with a sidebar and a few content cards, like a typical screenshot.
    private static func screenshot(accent: NSColor) -> Data {
        bitmap(width: 1440, height: 900) { size in
            NSColor(hex: 0xE9ECF2).setFill()
            NSRect(origin: .zero, size: size).fill()
            let window = NSRect(x: 120, y: 90, width: 1200, height: 720)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: window, xRadius: 18, yRadius: 18).fill()
            NSColor(hex: 0xF4F5F8).setFill()
            NSBezierPath(rect: NSRect(x: window.minX, y: window.minY, width: 260, height: window.height - 56)).fill()
            for (index, color) in [NSColor(hex: 0xFF5F57), NSColor(hex: 0xFEBC2E), NSColor(hex: 0x28C840)].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 24 + CGFloat(index) * 30, y: window.maxY - 38, width: 18, height: 18)).fill()
            }
            accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: window.minX + 300, y: window.maxY - 240, width: 520, height: 150), xRadius: 14, yRadius: 14).fill()
            for row in 0..<3 {
                NSColor(hex: 0xDDE1E8).setFill()
                NSBezierPath(roundedRect: NSRect(x: window.minX + 300, y: window.maxY - 330 - CGFloat(row) * 120, width: 840, height: 90), xRadius: 12, yRadius: 12).fill()
            }
        }.representation(using: .png, properties: [:])!
    }

    private static func logo() -> Data {
        bitmap(width: 800, height: 800) { size in
            NSColor(hex: 0xFFF4E5).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(hex: 0xF97316).setFill()
            NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 400, height: 400)).fill()
        }.representation(using: .png, properties: [:])!
    }

    private static func sunset() -> Data {
        bitmap(width: 1200, height: 900) { size in
            NSGradient(colors: [NSColor(hex: 0x2B1055), NSColor(hex: 0xD53A9D), NSColor(hex: 0xFFB36B)])?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
            NSColor(hex: 0xFFE29A).setFill()
            NSBezierPath(ovalIn: NSRect(x: 480, y: 300, width: 240, height: 240)).fill()
            NSColor(hex: 0x1B1033).setFill()
            let hills = NSBezierPath()
            hills.move(to: .zero)
            hills.line(to: CGPoint(x: 0, y: 320))
            hills.curve(to: CGPoint(x: 600, y: 260), controlPoint1: CGPoint(x: 220, y: 420), controlPoint2: CGPoint(x: 400, y: 200))
            hills.curve(to: CGPoint(x: 1200, y: 340), controlPoint1: CGPoint(x: 820, y: 320), controlPoint2: CGPoint(x: 1000, y: 420))
            hills.line(to: CGPoint(x: 1200, y: 0))
            hills.close()
            hills.fill()
        }.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    }

    /// A one-page "2019 tax return" PDF.
    private static func taxReturn(to url: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSString(string: "2019 TAX RETURN").draw(at: CGPoint(x: 60, y: 690), withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .heavy)])
        NSColor(hex: 0xCCD1D9).setFill()
        for line in 0..<14 {
            NSBezierPath(rect: NSRect(x: 60, y: 630 - CGFloat(line) * 36, width: line % 3 == 2 ? 300 : 490, height: 12)).fill()
        }
        NSColor(hex: 0xE5484D).setStroke()
        let stamp = NSBezierPath(roundedRect: NSRect(x: 330, y: 90, width: 230, height: 80), xRadius: 8, yRadius: 8)
        stamp.lineWidth = 6
        stamp.stroke()
        NSString(string: "OVERDUE").draw(at: CGPoint(x: 352, y: 108), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .black), .foregroundColor: NSColor(hex: 0xE5484D)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }
}
