import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {

    static var current: GlobalHotKey?

    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    static func registerOpenAria(action: @escaping () -> Void) -> GlobalHotKey? {
        GlobalHotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey), action: action)
    }

    private init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            GlobalHotKey.current?.action()
            return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: FourCharCode(1095651409), id: 1)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr else {
            return nil
        }
        hotKeyRef = ref
        GlobalHotKey.current = self
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }
}
