import AppKit
import SwiftUI

/// `Edgewise --snapshot <folder>` renders the popover offscreen in a few states and
/// appearances (used for the README). Draws through AppKit so real switches and
/// segmented controls appear, and needs no Screen Recording permission.
@MainActor
enum Snapshot {
    static func render(to folder: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let states: [(String, LinkState)] = [
            ("linked-left", .linked(side: .left, display: UUID())),
            ("linked-right", .linked(side: .right, display: UUID())),
            ("ready", .ready([.left, .right])),
            ("no-ipad", .noDevice),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (name, state) in states {
                let view = PopoverView(model: AppModel(preview: state))
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                    .padding(24)
                write(view, appearance: appearance, to: folder.appendingPathComponent("popover-\(name)-\(suffix).png"))
            }
            let overlay = OverlayContent(side: .right)
                .frame(width: 206, height: 64)
                .padding(24)
                .background(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.18, green: 0.22, blue: 0.36)],
                                           startPoint: .top, endPoint: .bottom))
            write(overlay, appearance: appearance, to: folder.appendingPathComponent("overlay-\(suffix).png"))
            for side in [Side.left, .right] {
                let icon = Image(nsImage: MenuBarIcon.image(for: .linked(side: side, display: UUID())))
                    .renderingMode(.template)
                    .foregroundStyle(Color.primary)
                    .scaleEffect(4)
                    .frame(width: 26 * 4 + 32, height: 16 * 4 + 32)
                    .background(Color(nsColor: .windowBackgroundColor))
                write(icon, appearance: appearance, to: folder.appendingPathComponent("menubar-\(side.rawValue)-\(suffix).png"))
            }
        }
        print("wrote snapshots to \(folder.path)")
    }

    private static func write<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = KeyWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        // Draw at 2x for crisp README images regardless of the current screen.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Draws controls in their active (key window) style.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}
