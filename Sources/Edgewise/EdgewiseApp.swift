import SwiftUI

@main
enum Entry {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let folder = CommandLine.arguments.dropFirst(index + 1).first ?? "."
            MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: folder)) }
            return
        }
        EdgewiseApp.main()
    }
}

struct EdgewiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: model.state))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    /// `edgewise://move/left`, `edgewise://move/right` and `edgewise://swap`, for Shortcuts,
    /// Raycast, Alfred, scripts and so on.
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), url.scheme == "edgewise" else { return }
        let parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        switch (parts.first, parts.dropFirst().first.flatMap(Side.init(rawValue:))) {
        case ("move", let side?):
            Task { await model.move(to: side, trigger: .url) }
        case ("swap", _):
            Task { await model.swap(trigger: .url) }
        default:
            log.error("unknown URL \(string, privacy: .public)")
        }
    }
}
