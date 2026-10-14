// Interface for the private UniversalControl.framework that ships with macOS.
//
// This file is never linked into anything. It is compiled with
// `-emit-module -enable-library-evolution` purely so Swift code can be type-checked
// against it; at runtime every call binds to the real framework through
// UniversalControl.tbd. Declarations therefore have to match the system framework's
// ABI exactly:
//
//   * @frozen types (passed in registers) must have the same stored layout.
//   * Resilient types are opaque to clients, so only their member signatures matter.
//
// Layouts were derived from call sites in /System/Library/CoreServices/UniversalControl.app
// on macOS 26.4. Bodies are placeholders and never execute.

import Foundation

// MARK: - Frozen value types

@frozen
public struct UniversalControlUUID {
    public var rawValue: uuid_t

    public init(uuid: UUID) { fatalError() }
    public init?(stringValue: String) { fatalError() }
    public var uuidValue: UUID { fatalError() }
    public var stringValue: String { fatalError() }
    public var description: String { fatalError() }
}

@frozen
public struct UniversalControlDeviceID {
    public var rawValue: UniversalControlUUID

    public init(uuid: UUID) { fatalError() }
    public init?(stringValue: String) { fatalError() }
    public var uuidValue: UUID { fatalError() }
    public var stringValue: String { fatalError() }
    public var label: String { fatalError() }
    public var description: String { fatalError() }
}

@frozen
public struct UniversalControlDisplayID {
    public var deviceID: UniversalControlDeviceID
    public var displayUUID: UniversalControlUUID

    public init(deviceID: UniversalControlDeviceID, displayUUID: UniversalControlUUID) { fatalError() }
    public var description: String { fatalError() }
}

/// Four cases; `Optional<UniversalControlEdge>.none` is tag 4.
@frozen
public enum UniversalControlEdge {
    case _0, _1, _2, _3

    public init?(intValue: Int) { fatalError() }
    public init?(stringValue: String) { fatalError() }
    public var intValue: Int { fatalError() }
    public var inverted: UniversalControlEdge { fatalError() }
    public var description: String { fatalError() }
}

// MARK: - Resilient value types

public struct UniversalControlAnchor {
    public init(edge: UniversalControlEdge, offset: Double) { fatalError() }
    public var edge: UniversalControlEdge { fatalError() }
    public var offset: Double { fatalError() }
}

public struct UniversalControlLink {
    public struct Endpoint {
        public init(display: UniversalControlDisplayID, anchor: UniversalControlAnchor) { fatalError() }
        public var display: UniversalControlDisplayID { fatalError() }
        public var anchor: UniversalControlAnchor { fatalError() }
        public var device: UniversalControlDeviceID { fatalError() }
    }

    public init(endpoint1: Endpoint, endpoint2: Endpoint) { fatalError() }
    public var endpoint1: Endpoint { fatalError() }
    public var endpoint2: Endpoint { fatalError() }
    public var edge: UniversalControlEdge { fatalError() }
    public var description: String { fatalError() }
}

public struct UniversalControlConfiguration {
    public struct GradedLink {
        public var link: UniversalControlLink { fatalError() }
        public var timestamp: Double { fatalError() }
        public var description: String { fatalError() }
    }

    public init(data: Data) throws { fatalError() }
    public func links() -> [GradedLink] { fatalError() }
    public func addingLinks(_ links: [UniversalControlLink]) -> UniversalControlConfiguration { fatalError() }
    public func removingLinks(where predicate: (UniversalControlLink) -> Bool) -> UniversalControlConfiguration { fatalError() }
    public func encoded() throws -> Data { fatalError() }
    public var digest: Data { fatalError() }
    public func prettyPrint() -> String { fatalError() }
}
