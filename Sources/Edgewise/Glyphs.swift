import AppKit
import SwiftUI

/// A Mac screen with an iPad beside it: the app's visual shorthand.
struct ArrangementGlyph: View {
    var side: Side?
    var filled: Bool

    var body: some View {
        Canvas { context, size in
            // Laid out in units: base overhang 2 + screen 14 + overhang 2, then a 1.4 gap and a 6.5-wide iPad.
            let unit = min(size.height / 13, size.width / 26)
            let total = 25.9 * unit
            let originX = (size.width - total) / 2
            let padOnLeft = side == .left
            let macX = originX + (padOnLeft ? 7.9 * unit : 0) + 2 * unit
            let mac = CGRect(x: macX, y: unit, width: 14 * unit, height: 9 * unit)
            context.stroke(Path(roundedRect: mac, cornerRadius: 1.5 * unit), with: .foreground, lineWidth: 1.4 * unit)
            context.fill(Path(roundedRect: CGRect(x: mac.minX - 2 * unit, y: mac.maxY + 1.2 * unit, width: mac.width + 4 * unit, height: 1.4 * unit),
                              cornerRadius: 0.7 * unit), with: .foreground)
            guard let side, side == .left || side == .right else { return }
            let width = 6.5 * unit
            let x = padOnLeft ? originX : mac.maxX + 3.4 * unit
            let pad = CGRect(x: x, y: 1.5 * unit, width: width, height: 9 * unit)
            let path = Path(roundedRect: pad, cornerRadius: 1.4 * unit)
            if filled { context.fill(path, with: .foreground) } else { context.stroke(path, with: .foreground, lineWidth: 1.2 * unit) }
        }
    }
}

/// The menu bar icon, drawn as a template image so it follows the menu bar's appearance.
enum MenuBarIcon {
    static func image(for state: LinkState) -> NSImage {
        let size = NSSize(width: 26, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            let mac = NSRect(x: 7.5, y: 2.5, width: 11, height: 7.5)
            let screen = NSBezierPath(roundedRect: mac, xRadius: 1.3, yRadius: 1.3)
            screen.lineWidth = 1.3
            screen.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 11.2, width: 15, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()

            func pad(_ x: CGFloat, filled: Bool) {
                let path = NSBezierPath(roundedRect: NSRect(x: x, y: 3, width: 4.5, height: 7), xRadius: 1, yRadius: 1)
                if filled { path.fill() } else { path.lineWidth = 1; path.stroke() }
            }
            switch state {
            case let .linked(side, _) where side == .left: pad(1, filled: true)
            case let .linked(side, _) where side == .right: pad(20.5, filled: true)
            case let .ready(sides):
                if sides.contains(.left) { pad(1.5, filled: false) }
                if sides.contains(.right) { pad(20, filled: false) }
            default: break
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Edgewise"
        return image
    }
}
