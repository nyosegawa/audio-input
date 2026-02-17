import Carbon

enum KeyCodes {
    static let space: UInt32 = UInt32(kVK_Space)
    static let returnKey: UInt32 = UInt32(kVK_Return)
    static let escape: UInt32 = UInt32(kVK_Escape)
}

struct HotkeyModifiers: OptionSet, Sendable {
    let rawValue: UInt32

    static let command = HotkeyModifiers(rawValue: UInt32(cmdKey))
    static let option = HotkeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotkeyModifiers(rawValue: UInt32(controlKey))
    static let shift = HotkeyModifiers(rawValue: UInt32(shiftKey))
}
