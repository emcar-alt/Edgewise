// edgewisectl: reads and rewrites the Universal Control arrangement.
//
// The arrangement lives in the ByHost preferences of `com.apple.universalcontrol` as a
// hash-chained log of links. Rather than re-implementing that format, this tool calls
// the system's own UniversalControl.framework (see PrivateAPI/) to decode it, append a
// link and re-encode it, so every digest is computed by Apple's code.
//
// It runs as a separate process so that if a future macOS changes the private API, only
// this helper fails (dyld refuses to bind it) and the menu bar app keeps running.

import AppKit
import Foundation
import UniversalControl

// MARK: - Output

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func emit(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// MARK: - Preferences

enum Store {
    static let domain = "com.apple.universalcontrol" as CFString
    static let configurationKey = "Configuration" as CFString
    static let configurationIDKey = "ConfigurationID" as CFString

    static func read(_ key: CFString) -> Data? {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Data
    }

    static func load() throws -> UniversalControlConfiguration {
        guard let data = read(configurationKey) else {
            throw Failure("No Universal Control arrangement is stored yet. Connect your iPad once by pushing the pointer through a screen edge.")
        }
        return try UniversalControlConfiguration(data: data)
    }

    static func save(_ configuration: UniversalControlConfiguration) throws {
        let data = try configuration.encoded()
        // Round-trip before writing so a bad encode never reaches the system.
        let check = try UniversalControlConfiguration(data: data)
        guard check.digest == configuration.digest else { throw Failure("Re-encoded arrangement failed verification; nothing was written.") }
        write(configuration: data, id: configuration.digest)
    }

    static func write(configuration: Data, id: Data) {
        CFPreferencesSetValue(configurationKey, configuration as CFData, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(configurationIDKey, id as CFData, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

// MARK: - Model helpers

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

/// The side of the Mac an iPad sits on, as seen from the Mac's display.
enum Side: String {
    case left, right, top, bottom

    var edge: UniversalControlEdge { UniversalControlEdge(stringValue: rawValue)! }
}

struct PeerLink {
    let graded: UniversalControlConfiguration.GradedLink
    let local: UniversalControlLink.Endpoint
    let peer: UniversalControlLink.Endpoint

    var link: UniversalControlLink { graded.link }
    var side: String { local.anchor.edge.description }

    var json: [String: Any] {
        [
            "peer": peer.device.uuidValue.uuidString,
            "macDisplay": local.display.displayUUID.uuidValue.uuidString,
            "side": side,
            "macOffset": local.anchor.offset,
            "peerOffset": peer.anchor.offset,
            "timestamp": graded.timestamp,
            "description": link.description,
        ]
    }
}

/// Every link between this Mac and another device, newest first.
func peerLinks(in configuration: UniversalControlConfiguration, mac: UUID) -> [PeerLink] {
    configuration.links().compactMap { graded -> PeerLink? in
        let link = graded.link
        let first = link.endpoint1, second = link.endpoint2
        if first.device.uuidValue == mac { return PeerLink(graded: graded, local: first, peer: second) }
        if second.device.uuidValue == mac { return PeerLink(graded: graded, local: second, peer: first) }
        return nil
    }
    .sorted { $0.graded.timestamp > $1.graded.timestamp }
}

/// This Mac's Universal Control device ID, from the agent itself.
func localDeviceID() throws -> UUID {
    if let override = ProcessInfo.processInfo.environment["EDGEWISE_MAC_ID"].flatMap(UUID.init(uuidString:)) { return override }
    if let id = try? Agent.edges().first?.device { return id }
    // No live edges (no iPad nearby). An endpoint on one of this Mac's online displays is ours.
    let online = Set(Screen.online().map(\.uuid))
    for graded in try Store.load().links() {
        for endpoint in [graded.link.endpoint1, graded.link.endpoint2] where online.contains(endpoint.display.displayUUID.uuidValue) {
            return endpoint.device.uuidValue
        }
    }
    throw Failure("Could not determine this Mac's Universal Control ID. Is Universal Control turned on?")
}

// MARK: - Displays

struct Screen {
    let uuid: UUID
    let frame: CGRect
    let isMain: Bool

    static func online() -> [Screen] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.compactMap { id in
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
                  let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, cfUUID) as String?,
                  let uuid = UUID(uuidString: string) else { return nil }
            return Screen(uuid: uuid, frame: CGDisplayBounds(id), isMain: CGDisplayIsMain(id) != 0)
        }
    }

    /// The display whose outer edge faces `side`.
    static func outermost(_ side: Side, among screens: [Screen]) -> Screen? {
        switch side {
        case .left: return screens.min { $0.frame.minX < $1.frame.minX }
        case .right: return screens.max { $0.frame.maxX < $1.frame.maxX }
        case .top: return screens.min { $0.frame.minY < $1.frame.minY }
        case .bottom: return screens.max { $0.frame.maxY < $1.frame.maxY }
        }
    }
}

// MARK: - Agent

enum Agent {
    struct EdgeRegion {
        let device: UUID
        let display: UUID
        let edge: String
        let rect: [Double]
    }

    /// Live edges where another device is attached, straight from the Universal Control agent.
    static func edges(timeout: TimeInterval = 3) throws -> [EdgeRegion] {
        let connection = NSXPCConnection(machServiceName: "com.apple.ensemble", options: [])
        let interface = NSXPCInterface(with: EnsembleBasic.self)
        let classes = NSSet(array: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSError.self,
                                    NSClassFromString("UniversalControlXPCEdgeRegion")!]) as! Set<AnyHashable>
        interface.setClasses(classes, for: #selector(EnsembleBasic.xpcGetEdges(completion:)), argumentIndex: 0, ofReply: true)
        connection.remoteObjectInterface = interface
        connection.resume()
        defer { connection.invalidate() }

        let done = DispatchSemaphore(value: 0)
        var result: Result<[EdgeRegion], Error> = .failure(Failure("Universal Control did not answer."))
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            result = .failure(error)
            done.signal()
        } as! EnsembleBasic
        proxy.xpcGetEdges { regions, error in
            if let error { result = .failure(error) } else { result = .success((regions ?? []).compactMap(decode)) }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else { throw Failure("Universal Control did not answer.") }
        return try result.get()
    }

    /// `UniversalControlXPCEdgeRegion` wraps a Swift struct; its NSCoding form is a plain
    /// dictionary under one key, so re-archive it and read that dictionary back.
    private static func decode(_ object: Any) -> EdgeRegion? {
        guard let object = object as? NSObject,
              let archive = try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(RegionBox.self, forClassName: NSStringFromClass(type(of: object)))
        guard let box = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? RegionBox,
              let region = box.region else { return nil }
        return regionFromDictionary(region)
    }

    @objc(EdgewiseRegionBox) private final class RegionBox: NSObject, NSCoding {
        let region: NSDictionary?
        init?(coder: NSCoder) { region = coder.decodeObject(forKey: "UniversalControlEdgeRegion") as? NSDictionary }
        func encode(with coder: NSCoder) {}
    }

    private static func regionFromDictionary(_ region: NSDictionary) -> EdgeRegion? {
        guard let id = region["id"] as? [String: Any],
              let device = (id["device"] as? String).flatMap(UUID.init(uuidString:)),
              let display = (id["display"] as? String).flatMap(UUID.init(uuidString:)),
              let edge = region["edge"] as? String else { return nil }
        let rect = (region["rect"] as? [NSNumber])?.map(\.doubleValue) ?? []
        return EdgeRegion(device: device, display: display, edge: edge, rect: rect)
    }

    static func waitForEdge(_ edge: String, on display: UUID, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let edges = try? edges(timeout: 1), edges.contains(where: { $0.edge == edge && $0.display == display }) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    /// Restarts the agent so it reloads the arrangement from preferences.
    static func restart() {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(uid)/com.apple.ensemble"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            // kickstart can be refused for platform agents; terminating works and launchd relaunches on demand.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.universalcontrol") { app.forceTerminate() }
        }
        // Any mach lookup relaunches it; wait until it answers again.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if (try? edges(timeout: 1)) != nil { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
}

@objc protocol EnsembleBasic {
    @objc(xpcGetEdgesWithCompletion:)
    func xpcGetEdges(completion: @escaping ([Any]?, Error?) -> Void)
}

// MARK: - Commands

func status() throws {
    let mac = try localDeviceID()
    let configuration = try Store.load()
    let links = peerLinks(in: configuration, mac: mac)
    var peers: [String: [String: Any]] = [:]
    for link in links where peers[link.peer.device.uuidValue.uuidString] == nil {
        peers[link.peer.device.uuidValue.uuidString] = link.json
    }
    let live = (try? Agent.edges()) ?? []
    emit([
        "mac": mac.uuidString,
        "configurationID": configuration.digest.hex,
        "peers": Array(peers.values),
        "liveEdges": live.map { ["display": $0.display.uuidString, "edge": $0.edge, "rect": $0.rect] },
        "screens": Screen.online().map { ["uuid": $0.uuid.uuidString, "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height], "main": $0.isMain] },
    ])
}

func set(side: Side, peer requestedPeer: UUID?, display requestedDisplay: UUID?, dryRun: Bool, reload: Bool) throws {
    let mac = try localDeviceID()
    let configuration = try Store.load()
    let links = peerLinks(in: configuration, mac: mac)
    guard let current = (requestedPeer.map { id in links.first { $0.peer.device.uuidValue == id } } ?? links.first) else {
        throw Failure("No iPad is linked to this Mac yet. Connect it once by pushing the pointer through a screen edge.")
    }
    let peerID = current.peer.device.uuidValue
    let screens = Screen.online()
    let targetDisplay = requestedDisplay
        ?? Screen.outermost(side, among: screens)?.uuid
        ?? current.local.display.displayUUID.uuidValue

    if current.side == side.rawValue && current.local.display.displayUUID.uuidValue == targetDisplay {
        emit(["changed": false, "side": side.rawValue, "peer": peerID.uuidString, "configurationID": configuration.digest.hex])
        return
    }

    let macDisplay = UniversalControlDisplayID(deviceID: UniversalControlDeviceID(uuid: mac),
                                               displayUUID: UniversalControlUUID(uuid: targetDisplay))
    let local = UniversalControlLink.Endpoint(display: macDisplay,
                                              anchor: UniversalControlAnchor(edge: side.edge, offset: current.local.anchor.offset))
    let peer = UniversalControlLink.Endpoint(display: current.peer.display,
                                             anchor: UniversalControlAnchor(edge: side.edge.inverted, offset: current.peer.anchor.offset))
    // Keep the endpoint order the system used for this pair.
    let macFirst = current.link.endpoint1.device.uuidValue == mac
    let link = macFirst ? UniversalControlLink(endpoint1: local, endpoint2: peer) : UniversalControlLink(endpoint1: peer, endpoint2: local)

    // Same as connecting through a magic edge: drop every link between the two devices, then add the new one.
    let updated = configuration
        .removingLinks { existing in
            let devices = [existing.endpoint1.device.uuidValue, existing.endpoint2.device.uuidValue]
            return devices.contains(mac) && devices.contains(peerID)
        }
        .addingLinks([link])

    var applied = "dry-run"
    if !dryRun {
        let wasLive = !((try? Agent.edges()) ?? []).isEmpty
        try Store.save(updated)
        // The agent watches its preferences and normally re-solves the layout within
        // milliseconds. Only restart it if the new edge doesn't show up.
        if !wasLive {
            applied = "stored"
        } else if Agent.waitForEdge(side.rawValue, on: targetDisplay, timeout: 1.5) {
            applied = "live"
        } else if reload {
            Agent.restart()
            applied = "restarted"
        } else {
            applied = "stored"
        }
    }
    emit([
        "changed": !dryRun,
        "applied": applied,
        "side": side.rawValue,
        "previousSide": current.side,
        "peer": peerID.uuidString,
        "display": targetDisplay.uuidString,
        "link": link.description,
        "configurationID": updated.digest.hex,
    ])
}

func backup(to path: String) throws {
    guard let configuration = Store.read(Store.configurationKey), let id = Store.read(Store.configurationIDKey) else {
        throw Failure("Nothing to back up.")
    }
    let plist: [String: Any] = ["Configuration": configuration, "ConfigurationID": id, "SavedAt": Date()]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    emit(["saved": path, "configurationID": id.hex])
}

func restore(from path: String, reload: Bool) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let configuration = plist["Configuration"] as? Data, let id = plist["ConfigurationID"] as? Data else {
        throw Failure("\(path) is not an Edgewise backup.")
    }
    guard try UniversalControlConfiguration(data: configuration).digest == id else { throw Failure("Backup failed verification.") }
    Store.write(configuration: configuration, id: id)
    if reload { Agent.restart() }
    emit(["restored": path, "configurationID": id.hex])
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: edgewisectl status
           edgewisectl set <left|right|top|bottom> [--peer UUID] [--display UUID] [--dry-run] [--no-reload]
           edgewisectl backup <file>
           edgewisectl restore <file> [--no-reload]
           edgewisectl reload
           edgewisectl dump

    """.utf8))
    exit(64)
}

// MARK: - Entry point

var arguments = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

do {
    let dryRun = flag("--dry-run")
    let reload = !flag("--no-reload")
    let peer = option("--peer").flatMap(UUID.init(uuidString:))
    let display = option("--display").flatMap(UUID.init(uuidString:))
    switch (arguments.first, arguments.count) {
    case ("status", 1): try status()
    case ("set", 2):
        guard let side = Side(rawValue: arguments[1]) else { usage() }
        try set(side: side, peer: peer, display: display, dryRun: dryRun, reload: reload)
    case ("backup", 2): try backup(to: arguments[1])
    case ("restore", 2): try restore(from: arguments[1], reload: reload)
    case ("reload", 1): Agent.restart(); emit(["reloaded": true])
    case ("dump", 1): print(try Store.load().prettyPrint())
    default: usage()
    }
} catch {
    FileHandle.standardError.write(Data("edgewisectl: \(error)\n".utf8))
    emit(["error": "\(error)"])
    exit(1)
}
