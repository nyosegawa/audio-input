import AppKit
import Carbon

@MainActor
final class TextInserter {
    private var previousClipboard: [NSPasteboard.PasteboardType: Data] = [:]

    func insert(text: String, targetPID: pid_t? = nil) async {
        let trusted = AXIsProcessTrusted()
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
        AppLogger.log("[INSERT] text=\(String(text.prefix(30))), AXTrusted=\(trusted), frontApp=\(frontApp), targetPID=\(targetPID ?? -1)")

        // Strategy 1: Direct Accessibility API insertion
        if insertViaAccessibility(text: text) {
            AppLogger.log("[INSERT] OK via AX direct insertion")
            return
        }

        // Strategy 2: Clipboard + Cmd+V
        if let pid = targetPID {
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if currentPID != pid {
                if let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
                    AppLogger.log("[INSERT] Re-activating \(targetApp.localizedName ?? "?") (PID \(pid))")
                    targetApp.activate()
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }

        saveClipboard()
        setClipboard(text: text)

        let changeCount = NSPasteboard.general.changeCount
        try? await Task.sleep(for: .milliseconds(80))

        AppLogger.log("[INSERT] Pasting via CGEvent, AXTrusted=\(AXIsProcessTrusted()), frontApp=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
        simulatePaste()

        // Restore clipboard after delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if NSPasteboard.general.changeCount == changeCount {
                self?.restoreClipboard()
            }
            self?.previousClipboard = [:]
        }
    }

    // MARK: - Accessibility API Direct Insertion

    private func insertViaAccessibility(text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef
        ) == .success else {
            AppLogger.log("[INSERT] AX: no focused app")
            return false
        }

        var focusedElemRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focusedAppRef as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElemRef
        ) == .success else {
            AppLogger.log("[INSERT] AX: no focused element")
            return false
        }

        let elem = focusedElemRef as! AXUIElement

        var roleRef: AnyObject?
        let role: String
        if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef) == .success {
            role = roleRef as? String ?? "unknown"
        } else {
            role = "unknown"
        }

        var isSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            elem, kAXSelectedTextAttribute as CFString, &isSettable
        ) == .success, isSettable.boolValue else {
            AppLogger.log("[INSERT] AX: role=\(role), selectedText not settable")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            elem, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        if result == .success {
            return true
        } else {
            AppLogger.log("[INSERT] AX: SetAttributeValue failed (\(result.rawValue))")
            return false
        }
    }

    // MARK: - Clipboard Paste Fallback

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
        let source = CGEventSource(stateID: .privateState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        usleep(20_000)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
