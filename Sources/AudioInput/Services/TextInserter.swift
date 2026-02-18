import AppKit
import Carbon

@MainActor
final class TextInserter {
    private var previousClipboard: [NSPasteboard.PasteboardType: Data] = [:]

    func insert(text: String) async {
        NSLog("[INSERT] Starting insert for text: %@", String(text.prefix(50)))
        saveClipboard()
        setClipboard(text: text)

        // Capture change count after we set the clipboard
        let changeCountAfterSet = NSPasteboard.general.changeCount
        NSLog("[INSERT] Clipboard set, changeCount: %d", changeCountAfterSet)

        // Small delay to ensure clipboard is set
        try? await Task.sleep(for: .milliseconds(50))

        NSLog("[INSERT] Simulating paste, AXIsProcessTrusted: %d", AXIsProcessTrusted() ? 1 : 0)
        simulatePaste()

        // Restore clipboard after delay, only if no external app modified it
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if NSPasteboard.general.changeCount == changeCountAfterSet {
                self?.restoreClipboard()
            }
            self?.previousClipboard = [:]
        }
    }

    private func saveClipboard() {
        let pasteboard = NSPasteboard.general
        previousClipboard = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                previousClipboard[type] = data
            }
        }
    }

    private func setClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func restoreClipboard() {
        guard !previousClipboard.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in previousClipboard {
            pasteboard.setData(data, forType: type)
        }
        previousClipboard = [:]
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Cmd+V key down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        // Cmd+V key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
