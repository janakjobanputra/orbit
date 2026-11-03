import AppKit

/// Orbit's ring-and-planet mark sized for the menu bar, for the Icon style.
enum MenuBarIcon {

    /// A template image, so macOS tints it to match the menu bar in light, dark and when highlighted.
    /// Drawn from the same geometry as the website logo (a 100-point square), scaled to 18 points.
    static let image: NSImage = {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let scale = size / 100
            func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: (x - radius) * scale, y: (y - radius) * scale, width: 2 * radius * scale, height: 2 * radius * scale))
            }
            // The ring is lighter than the planets, as in the logo; a template keeps that through its alpha.
            let ring = circle(50, 50, 36)
            ring.lineWidth = 8 * scale
            NSColor.black.withAlphaComponent(0.5).setStroke()
            ring.stroke()
            NSColor.black.setFill()
            circle(50, 50, 19).fill()
            circle(75.5, 24.5, 10).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orbit"
        return image
    }()
}
