import Carbon.HIToolbox

/// ⌃⌥⌘← and ⌃⌥⌘→ move the iPad left or right. Carbon hot keys work without any
/// Accessibility or Input Monitoring permission.
@MainActor
final class HotKeys {
    var onMove: ((Side) -> Void)?

    private var references: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4547_5745 // 'EGWE'

    func register() {
        guard references.isEmpty else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let context, id.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.onMove?(id.id == 1 ? .left : .right) }
            return noErr
        }, 1, &type, context, &handler)

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for (number, key) in [(UInt32(1), kVK_LeftArrow), (UInt32(2), kVK_RightArrow)] {
            var reference: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), modifiers, EventHotKeyID(signature: Self.signature, id: number),
                                GetApplicationEventTarget(), 0, &reference)
            references.append(reference)
        }
    }

    func unregister() {
        references.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
