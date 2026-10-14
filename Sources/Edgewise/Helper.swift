import Foundation

/// Runs the bundled `edgewisectl`, the only part of Edgewise that touches the private
/// UniversalControl framework. Keeping it out of process means an incompatible macOS
/// release makes the helper fail to launch instead of crashing the menu bar app.
enum Helper {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct MoveResult: Decodable {
        let changed: Bool
        let applied: String?
        let side: String
        let previousSide: String?
    }

    static var url: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/edgewisectl")
    }

    static func move(to side: Side, display: UUID?) async throws -> MoveResult {
        var arguments = ["set", side.rawValue]
        if let display { arguments += ["--display", display.uuidString] }
        return try JSONDecoder().decode(MoveResult.self, from: try await run(arguments))
    }

    static func backup(to file: URL) async throws {
        try await run(["backup", file.path])
    }

    static let incompatibleMessage = "This macOS version changed Universal Control's internals, so Edgewise can't move the iPad until it's updated."

    /// A message when the helper can't bind to this macOS version's UniversalControl
    /// framework; nil when it can (other errors, like no iPad yet, don't count).
    static func compatibilityProblem() async -> String? {
        do {
            try await run(["status"])
            return nil
        } catch let failure as Failure where failure.message == incompatibleMessage {
            return failure.message
        } catch {
            return nil
        }
    }

    @discardableResult
    static func run(_ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runSync(arguments) })
            }
        }
    }

    private static func runSync(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw Failure(message: "Couldn't start edgewisectl: \(error.localizedDescription)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return data }
        if process.terminationReason == .uncaughtSignal || message.contains("Symbol not found") {
            throw Failure(message: incompatibleMessage)
        }
        let text = message.replacingOccurrences(of: "edgewisectl: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        throw Failure(message: text.isEmpty ? "edgewisectl exited with status \(process.terminationStatus)." : text)
    }
}
