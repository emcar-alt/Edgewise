import AppKit

/// How hard you have to push against a screen edge before Edgewise moves the iPad there.
enum Sensitivity: String, CaseIterable, Identifiable {
    case light, medium, firm

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Pointer travel (in points, after acceleration) that has to pile up against the edge.
    var threshold: CGFloat {
        switch self {
        case .light: 160
        case .medium: 320
        case .firm: 600
        }
    }
}

/// Decides when a run of pointer movement counts as a deliberate push through a screen
/// edge. Pure value type so it can be exercised without real events (see Tests/).
struct PushAccumulator {
    struct Sample {
        /// The outer edge the pointer is pinned against, or nil when it isn't at one.
        var pinnedEdge: Side?
        /// Movement this event, positive toward `pinnedEdge`'s outside.
        var outward: CGFloat
        var time: TimeInterval
    }

    var threshold: CGFloat
    /// A push has to be one continuous motion: a gap longer than this starts over.
    var maxGap: TimeInterval = 0.3
    /// ...and has to reach the threshold within this window.
    var window: TimeInterval = 1.5

    private(set) var edge: Side?
    private(set) var total: CGFloat = 0
    private var start: TimeInterval = 0
    private var last: TimeInterval = 0

    init(threshold: CGFloat) { self.threshold = threshold }

    var progress: CGFloat { min(total / threshold, 1) }

    /// Feeds one event; returns the edge once the push crosses the threshold.
    mutating func add(_ sample: Sample) -> Side? {
        guard let pinned = sample.pinnedEdge else { reset(); return nil }
        if pinned != edge || sample.time - last > maxGap || sample.time - start > window {
            edge = pinned
            total = 0
            start = sample.time
        }
        last = sample.time
        if sample.outward < -2 {
            // Pulling back off the edge cancels the push.
            total = 0
            start = sample.time
            return nil
        }
        total += max(sample.outward, 0)
        guard total >= threshold else { return nil }
        reset()
        return pinned
    }

    mutating func reset() {
        edge = nil
        total = 0
    }
}

/// Watches global pointer movement and reports deliberate pushes against outer screen edges.
@MainActor
final class EdgePushDetector {
    /// Called with the pushed edge and the display it belongs to.
    var onPush: ((Side, NSScreen) -> Void)?
    /// Called once, when the first pointer event arrives (useful to confirm monitoring works).
    var onFirstEvent: (() -> Void)?
    /// Edges that may trigger. Everything else is ignored.
    var armedSides: Set<Side> = []
    var sensitivity: Sensitivity = .medium {
        didSet { accumulator.threshold = sensitivity.threshold }
    }

    private var accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
    private var monitor: Any?
    private var cooldownUntil: TimeInterval = 0
    private var hasSeenEvents = false

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        // Global mouse-move monitors need no Accessibility or Input Monitoring permission.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulator.reset()
    }

    private func handle(_ event: NSEvent) {
        if !hasSeenEvents {
            hasSeenEvents = true
            onFirstEvent?()
        }
        let now = event.timestamp
        guard now >= cooldownUntil, !armedSides.isEmpty else { return }
        let point = NSEvent.mouseLocation
        guard let screen = Displays.screen(containing: point) else { return }
        let frame = screen.frame

        var pinned: Side?
        var outward: CGFloat = 0
        // deltaX grows to the right; deltaY grows downward.
        if point.x <= frame.minX + 0.5, armedSides.contains(.left) {
            pinned = .left; outward = -event.deltaX
        } else if point.x >= frame.maxX - 1.5, armedSides.contains(.right) {
            pinned = .right; outward = event.deltaX
        } else if point.y >= frame.maxY - 1.5, armedSides.contains(.top) {
            pinned = .top; outward = -event.deltaY
        } else if point.y <= frame.minY + 0.5, armedSides.contains(.bottom) {
            pinned = .bottom; outward = event.deltaY
        }
        if let side = pinned, !Displays.isOuterEdge(side, of: screen, at: point) { pinned = nil }

        if let side = accumulator.add(.init(pinnedEdge: pinned, outward: outward, time: now)) {
            cooldownUntil = now + 2
            onPush?(side, screen)
        }
    }
}
