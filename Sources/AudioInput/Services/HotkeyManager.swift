import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var nextHotkeyID: UInt32 = 1

    // Static reference for C callback
    nonisolated(unsafe) private static var shared: HotkeyManager?

    func register(keyCode: UInt32, modifiers: UInt32, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        HotkeyManager.shared = self

        installEventHandlerIfNeeded()
        registerHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Register an additional hotkey that triggers the same callbacks
    func registerAdditional(keyCode: UInt32, modifiers: UInt32) {
        registerHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        var carbonModifiers: UInt32 = 0
        if modifiers & UInt32(optionKey) != 0 { carbonModifiers |= UInt32(optionKey) }
        if modifiers & UInt32(cmdKey) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if modifiers & UInt32(controlKey) != 0 { carbonModifiers |= UInt32(controlKey) }
        if modifiers & UInt32(shiftKey) != 0 { carbonModifiers |= UInt32(shiftKey) }

        let hotkeyID = EventHotKeyID(signature: OSType(0x4149_4E50), id: nextHotkeyID)
        nextHotkeyID += 1

        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            keyCode, carbonModifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        if let ref = ref {
            hotkeyRefs.append(ref)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

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
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
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
