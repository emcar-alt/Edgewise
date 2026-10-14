import AppKit
import ServiceManagement
import SwiftUI
import SystemConfiguration
import os

let log = Logger(subsystem: "com.ethanmathias.Edgewise", category: "app")

/// What Universal Control is doing with the iPad right now.
enum LinkState: Equatable {
    /// Waiting for the first answer from the agent.
    case unknown
    /// The agent didn't answer (Universal Control is off or restarting).
    case agentUnreachable
    /// No iPad is attached or nearby.
    case noDevice
    /// Not linked yet: Universal Control will connect on whichever of these edges you push through.
    case ready([Side])
    /// Linked on one edge of a display.
    case linked(side: Side, display: UUID)

    var side: Side? {
        if case let .linked(side, _) = self { return side }
        return nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: LinkState = .unknown
    @Published private(set) var isMoving = false
    @Published private(set) var lastError: String?

    @Published var followPointer: Bool { didSet { defaults.set(followPointer, forKey: Keys.followPointer); configureDetector() } }
    @Published var sensitivity: Sensitivity { didSet { defaults.set(sensitivity.rawValue, forKey: Keys.sensitivity); detector.sensitivity = sensitivity } }
    @Published var hotKeysEnabled: Bool { didSet { defaults.set(hotKeysEnabled, forKey: Keys.hotKeys); configureHotKeys() } }
    @Published var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.overlay) } }
    @Published var openAtLogin: Bool { didSet { setOpenAtLogin(openAtLogin) } }
    let macName: String

    enum Trigger: String { case push, shortcut, menu, url }

    private enum Keys {
        static let followPointer = "FollowPointer"
        static let sensitivity = "PushSensitivity"
        static let hotKeys = "HotKeysEnabled"
        static let overlay = "ShowOverlay"
    }

    private let defaults = UserDefaults.standard
    private let detector = EdgePushDetector()
    private let hotKeys = HotKeys()
    private let overlay = SwitchOverlay()
    private var pollTask: Task<Void, Never>?

    init() {
        defaults.register(defaults: [Keys.followPointer: true, Keys.sensitivity: Sensitivity.medium.rawValue,
                                     Keys.hotKeys: true, Keys.overlay: true])
        followPointer = defaults.bool(forKey: Keys.followPointer)
        sensitivity = Sensitivity(rawValue: defaults.string(forKey: Keys.sensitivity) ?? "") ?? .medium
        hotKeysEnabled = defaults.bool(forKey: Keys.hotKeys)
        showOverlay = defaults.bool(forKey: Keys.overlay)
        openAtLogin = SMAppService.mainApp.status == .enabled
        macName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "This Mac"
        wire()
    }

    /// A model frozen in `state` with default settings, for snapshots. Starts nothing.
    init(preview state: LinkState) {
        followPointer = true
        sensitivity = .medium
        hotKeysEnabled = true
        showOverlay = true
        openAtLogin = false
        macName = "MacBook Pro"
        self.state = state
    }

    private func wire() {
        detector.sensitivity = sensitivity
        detector.onFirstEvent = { log.info("pointer monitor is receiving events") }
        detector.onPush = { [weak self] side, screen in
            Task { await self?.move(to: side, on: screen, trigger: .push) }
        }
        hotKeys.onMove = { [weak self] side in
            Task { await self?.move(to: side, on: nil, trigger: .shortcut) }
        }
        configureHotKeys()
    }

    func start() {
        guard pollTask == nil else { return }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
        pollTask = Task { [weak self] in
            if let problem = await Helper.compatibilityProblem() {
                log.error("helper: \(problem, privacy: .public)")
                self?.lastError = problem
            }
            await self?.backUpOriginalArrangement()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() async {
        guard let edges = await UniversalControlAgent.edges() else {
            update(.agentUnreachable)
            return
        }
        switch edges.count {
        case 0: update(.noDevice)
        case 1: update(.linked(side: edges[0].side, display: edges[0].display))
        default: update(.ready(Array(Set(edges.map(\.side))).sorted { $0.rawValue < $1.rawValue }))
        }
    }

    private func update(_ newState: LinkState) {
        if state != newState {
            log.info("state: \(String(describing: newState), privacy: .public)")
            state = newState
        }
        configureDetector()
    }

    // MARK: Moving

    func move(to side: Side, on screen: NSScreen? = nil, trigger: Trigger) async {
        guard !isMoving else { return }
        isMoving = true
        defer { isMoving = false }
        let screen = screen ?? Displays.outermost(side)
        log.info("move to \(side.rawValue, privacy: .public) (\(trigger.rawValue, privacy: .public))")
        do {
            let result = try await Helper.move(to: side, display: screen.flatMap(Displays.uuid))
            log.info("moved: changed=\(result.changed) applied=\(result.applied ?? "-", privacy: .public)")
            lastError = nil
            if showOverlay, let screen { overlay.show(side: side, on: screen) }
        } catch {
            log.error("move failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// Moves the iPad to the other side (left ↔ right).
    func swap(trigger: Trigger) async {
        await refresh()
        await move(to: state.side == .left ? .right : .left, trigger: trigger)
    }

    // MARK: Wiring

    private func configureDetector() {
        // Only push-to-move while linked: when Universal Control is still searching it already
        // connects on whichever edge you push through.
        guard followPointer, case let .linked(side, _) = state else {
            detector.armedSides = []
            detector.stop()
            return
        }
        let armed = Set([Side.left, .right]).subtracting([side])
        if detector.armedSides != armed || !detector.isRunning {
            log.info("watching for pushes: \(armed.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
        }
        detector.armedSides = armed
        detector.start()
    }

    private func configureHotKeys() {
        hotKeysEnabled ? hotKeys.register() : hotKeys.unregister()
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Couldn't update Open at Login: \(error.localizedDescription)"
        }
    }

    /// Saves the arrangement as it was before Edgewise ever touched it, once.
    private func backUpOriginalArrangement() async {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = support.appendingPathComponent("Edgewise", isDirectory: true)
        let file = folder.appendingPathComponent("Original Arrangement.plist")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? await Helper.backup(to: file)
    }

    func openDisplaySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }
}
