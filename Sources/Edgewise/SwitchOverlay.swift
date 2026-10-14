import AppKit
import SwiftUI

/// A small, click-through overlay at the screen edge confirming where the iPad went.
@MainActor
final class SwitchOverlay {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(side: Side, on screen: NSScreen) {
        let size = NSSize(width: 206, height: 64)
        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel
        panel.contentView = NSHostingView(rootView: OverlayContent(side: side).frame(width: size.width, height: size.height))

        let frame = screen.visibleFrame
        let inset: CGFloat = 24
        var origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        switch side {
        case .left: origin.x = frame.minX + inset
        case .right: origin.x = frame.maxX - size.width - inset
        case .top: origin.y = frame.maxY - size.height - inset
        case .bottom: origin.y = frame.minY + inset
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel?.animator().alphaValue = 0 }) { panel?.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}

struct OverlayContent: View {
    let side: Side

    var body: some View {
        HStack(spacing: 12) {
            ArrangementGlyph(side: side, filled: true)
                .frame(width: 44, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("iPad").font(.system(size: 13, weight: .semibold))
                Text("now on the \(side.rawValue)").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}
