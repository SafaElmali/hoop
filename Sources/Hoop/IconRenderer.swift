import AppKit

/// Draws the app icon; build.sh calls `Hoop --render-icon <png>` and turns it into an .icns.
enum IconRenderer {
    static func write(to url: URL) {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func draw(in context: CGContext) {
        // Tile on the macOS icon grid (824 pt inside 1024), with a soft drop shadow.
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.white.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: .white, ending: NSColor(hex: 0xE9ECF2))?.draw(in: tile, angle: -90)

        let ink = NSColor(hex: 0xA1A7B3)
        let rimCenter = CGPoint(x: 512, y: 430)
        let rimRadii = CGSize(width: 220, height: 40)

        let board = NSBezierPath(roundedRect: NSRect(x: 337, y: rimCenter.y + 56, width: 350, height: 250), xRadius: 24, yRadius: 24)
        NSColor.white.setFill()
        board.fill()
        ink.setStroke()
        board.lineWidth = 16
        board.stroke()

        let bracket = NSBezierPath()
        bracket.move(to: CGPoint(x: 452, y: rimCenter.y + 28))
        bracket.line(to: CGPoint(x: 572, y: rimCenter.y + 28))
        bracket.line(to: CGPoint(x: 554, y: rimCenter.y + 64))
        bracket.line(to: CGPoint(x: 470, y: rimCenter.y + 64))
        bracket.close()
        Palette.rim.setFill()
        bracket.fill()

        // Back of the hoop, then the file dropping in, then the front, so the file sits inside the rim.
        let net = NetGeometry.segments(rx: rimRadii.width, ry: rimRadii.height, height: 260)
        stroke(.lines(net.back), in: context, at: rimCenter, color: ink.withAlphaComponent(0.45), width: 9)
        stroke(.ellipseArc(radii: rimRadii, from: 0, to: .pi), in: context, at: rimCenter,
               color: Palette.rim.blended(withFraction: 0.3, of: .black) ?? Palette.rim, width: 30)
        drawFile(at: CGPoint(x: 530, y: rimCenter.y + 95), degrees: -14)
        stroke(.lines(net.front), in: context, at: rimCenter, color: ink, width: 12)
        stroke(.ellipseArc(radii: rimRadii, from: .pi, to: 2 * .pi), in: context, at: rimCenter, color: Palette.rim, width: 36)
    }

    private static func stroke(_ path: CGPath, in context: CGContext, at origin: CGPoint, color: NSColor, width: CGFloat) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// A document with a folded corner and an image glyph, like the one in the hoop.
    private static func drawFile(at center: CGPoint, degrees: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: degrees)
        transform.concat()

        let width: CGFloat = 170, height: CGFloat = 210, fold: CGFloat = 46
        let page = NSBezierPath()
        page.move(to: CGPoint(x: -width / 2, y: -height / 2))
        page.line(to: CGPoint(x: width / 2, y: -height / 2))
        page.line(to: CGPoint(x: width / 2, y: height / 2 - fold))
        page.line(to: CGPoint(x: width / 2 - fold, y: height / 2))
        page.line(to: CGPoint(x: -width / 2, y: height / 2))
        page.close()
        page.lineJoinStyle = .round
        NSColor.white.setFill()
        page.fill()
        NSColor(hex: 0xC9CED6).setStroke()
        page.lineWidth = 8
        page.stroke()

        NSColor(hex: 0xD5D9E0).setFill()
        NSBezierPath(roundedRect: NSRect(x: -52, y: 52, width: 56, height: 12), xRadius: 6, yRadius: 6).fill()

        NSColor(hex: 0xF0804A).setFill()
        NSBezierPath(roundedRect: NSRect(x: -52, y: -62, width: 104, height: 80), xRadius: 12, yRadius: 12).fill()
        let mountains = NSBezierPath()
        mountains.move(to: CGPoint(x: -40, y: -52))
        mountains.line(to: CGPoint(x: -12, y: -18))
        mountains.line(to: CGPoint(x: 6, y: -38))
        mountains.line(to: CGPoint(x: 18, y: -26))
        mountains.line(to: CGPoint(x: 42, y: -52))
        mountains.close()
        NSColor.white.setFill()
        mountains.fill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: -8, width: 18, height: 18)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
