import Foundation

/// A screen edge of this Mac where another device is attached, as reported live by the
/// Universal Control agent (`com.apple.ensemble`).
struct AgentEdge: Equatable {
    let device: UUID
    let display: UUID
    let side: Side
}

/// Read-only client for the Universal Control agent.
///
/// `xpcGetEdgesWithCompletion:` is the one call the agent answers for ordinary apps (the
/// rest of its interface requires an Apple entitlement), and it is all Edgewise needs to
/// know where the iPad is right now. Writes go through `edgewisectl`.
enum UniversalControlAgent {
    static func edges(timeout: TimeInterval = 2) async -> [AgentEdge]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: edgesSync(timeout: timeout))
            }
        }
    }

    static func edgesSync(timeout: TimeInterval) -> [AgentEdge]? {
        let connection = NSXPCConnection(machServiceName: "com.apple.ensemble", options: [])
        let interface = NSXPCInterface(with: EnsembleBasicInterface.self)
        let classes = NSSet(array: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSError.self, XPCEdgeRegion.self])
        interface.setClasses(classes as! Set<AnyHashable>, for: #selector(EnsembleBasicInterface.xpcGetEdges(completion:)), argumentIndex: 0, ofReply: true)
        connection.remoteObjectInterface = interface
        connection.resume()
        defer { connection.invalidate() }

        let done = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in done.signal() } as? EnsembleBasicInterface
        proxy?.xpcGetEdges { regions, error in
            if error == nil { box.edges = (regions ?? []).compactMap { ($0 as? XPCEdgeRegion)?.edge } }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.edges
    }

    private final class ResultBox: @unchecked Sendable {
        var edges: [AgentEdge]?
    }
}

@objc private protocol EnsembleBasicInterface {
    @objc(xpcGetEdgesWithCompletion:)
    func xpcGetEdges(completion: @escaping ([Any]?, Error?) -> Void)
}

/// Stand-in for the agent's `UniversalControlXPCEdgeRegion`. Registering a class under that
/// name lets NSXPC decode replies without loading the private framework into this process.
/// The payload is `{ id: { device, display }, edge: "left", rect: [...] }`, sent over XPC as
/// encoded data (and as a plain dictionary when keyed-archived).
@objc(UniversalControlXPCEdgeRegion)
final class XPCEdgeRegion: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let edge: AgentEdge?

    init?(coder: NSCoder) {
        let classes = [NSData.self, NSDictionary.self, NSArray.self, NSString.self, NSNumber.self]
        let payload = coder.decodeObject(of: classes, forKey: "UniversalControlEdgeRegion")
        let region = (payload as? [String: Any]) ?? (payload as? Data).flatMap(Self.dictionary(from:))
        let id = region?["id"] as? [String: Any]
        if let device = (id?["device"] as? String).flatMap(UUID.init(uuidString:)),
           let display = (id?["display"] as? String).flatMap(UUID.init(uuidString:)),
           let side = (region?["edge"] as? String).flatMap(Side.init(rawValue:)) {
            edge = AgentEdge(device: device, display: display, side: side)
        } else {
            edge = nil
        }
    }

    func encode(with coder: NSCoder) {}

    private static func dictionary(from data: Data) -> [String: Any]? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] { return plist }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
