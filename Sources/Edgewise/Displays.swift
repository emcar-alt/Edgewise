import AppKit

enum Side: String, CaseIterable, Codable {
    case left, right, top, bottom

    var opposite: Side {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    var title: String { rawValue.capitalized }
}

/// Geometry helpers over the current display arrangement, in Cocoa global coordinates
/// (origin at the bottom-left of the primary display).
enum Displays {
    static func uuid(of screen: NSScreen) -> UUID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, cfUUID) as String? else { return nil }
        return UUID(uuidString: string)
    }

    static func screen(withUUID uuid: UUID) -> NSScreen? {
        NSScreen.screens.first { Displays.uuid(of: $0) == uuid }
    }

    /// The screen under `point`, treating each screen's right/top edge as inclusive so the
    /// pointer pinned against the last pixel column still counts.
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// Whether `side` of `screen` is an outer edge at height `y` (no other display continues there).
    static func isOuterEdge(_ side: Side, of screen: NSScreen, at point: NSPoint) -> Bool {
        let frame = screen.frame
        let probe: NSPoint
        switch side {
        case .left: probe = NSPoint(x: frame.minX - 2, y: point.y)
        case .right: probe = NSPoint(x: frame.maxX + 2, y: point.y)
        case .top: probe = NSPoint(x: point.x, y: frame.maxY + 2)
        case .bottom: probe = NSPoint(x: point.x, y: frame.minY - 2)
        }
        return !NSScreen.screens.contains { $0 != screen && $0.frame.contains(probe) }
    }

    /// The display whose outer edge faces `side` across the whole arrangement.
    static func outermost(_ side: Side) -> NSScreen? {
        switch side {
        case .left: NSScreen.screens.min { $0.frame.minX < $1.frame.minX }
        case .right: NSScreen.screens.max { $0.frame.maxX < $1.frame.maxX }
        case .top: NSScreen.screens.max { $0.frame.maxY < $1.frame.maxY }
        case .bottom: NSScreen.screens.min { $0.frame.minY < $1.frame.minY }
        }
    }
}
