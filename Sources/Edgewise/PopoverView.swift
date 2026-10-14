import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            ArrangementPicker(model: model)
                .padding(.horizontal, 16)

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 14)

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SettingRow(title: "Follow my pointer",
                           detail: "Push the pointer past the empty edge and your iPad moves there.",
                           isOn: $model.followPointer)
                if model.followPointer {
                    HStack {
                        Text("Push strength").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Push strength", selection: $model.sensitivity) {
                            ForEach(Sensitivity.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 168)
                    }
                    .padding(.leading, 2)
                }
                SettingRow(title: "Keyboard shortcuts", detail: "⌃⌥⌘← and ⌃⌥⌘→ move the iPad.", isOn: $model.hotKeysEnabled)
                SettingRow(title: "Show overlay", detail: nil, isOn: $model.showOverlay)
                SettingRow(title: "Open at login", detail: nil, isOn: $model.openAtLogin)
            }
            .padding(16)

            Divider()

            HStack(spacing: 14) {
                Button("Displays Settings…") { model.openDisplaySettings() }
                Spacer()
                Text("v\(Bundle.main.shortVersion)").foregroundStyle(.tertiary)
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("Edgewise").font(.system(size: 14, weight: .semibold))
            Spacer()
            StatusPill(state: model.state, isMoving: model.isMoving)
        }
    }

    private var caption: String {
        switch model.state {
        case .unknown: "Checking Universal Control…"
        case .agentUnreachable: "Universal Control isn't responding. Is it turned on?"
        case .noDevice: "No iPad nearby. Edgewise will be ready when it is."
        case .ready: "Push the pointer toward your iPad to connect."
        case let .linked(side, _): "Your iPad is on the \(side.rawValue)."
        }
    }
}

private struct StatusPill: View {
    let state: LinkState
    let isMoving: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var title: String {
        if isMoving { return "Moving…" }
        switch state {
        case .unknown: return "Checking"
        case .agentUnreachable: return "Off"
        case .noDevice: return "No iPad"
        case .ready: return "Ready"
        case let .linked(side, _): return "Linked · \(side.title)"
        }
    }

    private var color: Color {
        if isMoving { return .blue }
        switch state {
        case .linked: return .green
        case .ready: return .orange
        default: return .gray
        }
    }
}

/// Mac in the middle, a slot on each side. Click the empty slot to move the iPad there.
private struct ArrangementPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            slot(.left)
            MacTile(name: model.macName)
            slot(.right)
        }
        .frame(height: 84)
    }

    private func slot(_ side: Side) -> some View {
        let occupied = model.state.side == side
        let ready: Bool = {
            if case let .ready(sides) = model.state { return sides.contains(side) }
            return false
        }()
        return Button {
            Task { await model.move(to: side, trigger: .menu) }
        } label: {
            IPadSlot(occupied: occupied, ready: ready, side: side)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!occupied && !model.isMoving)
        .help(occupied ? "Your iPad is here" : "Move iPad to the \(side.rawValue)")
    }
}

private struct MacTile: View {
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: NSScreen.screens.count > 1 ? "display.2" : "laptopcomputer")
                .font(.system(size: 30, weight: .light))
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct IPadSlot: View {
    let occupied: Bool
    let ready: Bool
    let side: Side
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 5) {
            Image(systemName: occupied ? "ipad" : "plus")
                .font(.system(size: occupied ? 24 : 14, weight: occupied ? .regular : .medium))
            Text(occupied ? "iPad" : hovering ? "Move here" : side.title)
                .font(.system(size: 10.5, weight: occupied ? .semibold : .regular))
        }
        .foregroundStyle(occupied ? Color.white : hovering ? Brand.blue : Color.secondary)
        .frame(width: 70)
        .frame(maxHeight: .infinity)
        .background(occupied ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear), in: shape)
        .shadow(color: occupied ? Brand.indigo.opacity(0.35) : .clear, radius: 6, y: 3)
        .overlay {
            if !occupied {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: ready ? [] : [4, 3]))
                    .foregroundStyle(hovering || ready ? Brand.blue.opacity(0.8) : Color.secondary.opacity(0.45))
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: occupied)
    }
}

private struct SettingRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(BrandSwitchStyle())
        }
    }
}

/// Colors from the app icon.
enum Brand {
    static let indigo = Color(red: 0.26, green: 0.22, blue: 0.80)
    static let blue = Color(red: 0.13, green: 0.47, blue: 0.86)
    static let gradient = LinearGradient(colors: [indigo, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A compact switch in the brand color. Pure SwiftUI, so it renders the same in the menu
/// bar window and in offscreen snapshots.
struct BrandSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Capsule()
            .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.14)))
            .frame(width: 32, height: 19)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 1.2, y: 0.6)
                    .padding(2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: on)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
}
