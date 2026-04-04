// Yappie/TextDelivery.swift
import AppKit
import Carbon

enum DeliveryMode: String {
    case clipboardAndPaste = "clipboard-and-paste"
    case clipboardOnly = "clipboard-only"
}

enum TextDelivery {
    static func deliver(_ text: String, mode: DeliveryMode) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if mode == .clipboardAndPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                simulatePaste()
            }
        }
    }

    static func checkAccessibility(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
