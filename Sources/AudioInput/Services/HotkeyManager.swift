import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?

    // Static reference for C callback
    nonisolated(unsafe) private static var shared: HotkeyManager?

    func register(keyCode: UInt32, modifiers: UInt32, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        HotkeyManager.shared = self

        // Convert to Carbon modifier format
        var carbonModifiers: UInt32 = 0
        if modifiers & UInt32(optionKey) != 0 { carbonModifiers |= UInt32(optionKey) }
        if modifiers & UInt32(cmdKey) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if modifiers & UInt32(controlKey) != 0 { carbonModifiers |= UInt32(controlKey) }
        if modifiers & UInt32(shiftKey) != 0 { carbonModifiers |= UInt32(shiftKey) }

        let hotkeyID = EventHotKeyID(signature: OSType(0x4149_4E50), id: 1)  // "AINP"
        var hotKeyIDVar = hotkeyID

        // Register for key down
        RegisterEventHotKey(
            keyCode, carbonModifiers, hotKeyIDVar, GetApplicationEventTarget(), 0, &hotkeyRef)

        // Install event handler for hotkey events
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event = event else { return OSStatus(eventNotHandledErr) }
                let eventKind = GetEventKind(event)

                Task { @MainActor in
                    if eventKind == UInt32(kEventHotKeyPressed) {
                        HotkeyManager.shared?.onKeyDown?()
                    } else if eventKind == UInt32(kEventHotKeyReleased) {
                        HotkeyManager.shared?.onKeyUp?()
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandler
        )
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        HotkeyManager.shared = nil
    }

    deinit {
        // Can't call unregister() from deinit in MainActor context
    }
}
