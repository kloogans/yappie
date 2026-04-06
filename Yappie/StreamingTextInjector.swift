// Yappie/StreamingTextInjector.swift
import AppKit
import Carbon

enum StreamingTextInjector {
    private static let maxUniCharPerEvent = 20

    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        debugLog("[Yappie] StreamingTextInjector.type: '\(text)' (\(text.count) chars)")
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)

        for chunk in stride(from: 0, to: utf16.count, by: maxUniCharPerEvent) {
            let end = min(chunk + maxUniCharPerEvent, utf16.count)
            var chars = Array(utf16[chunk..<end])
            let len = chars.count

            // Use VK_SPACE as the base keycode — harmless if unicode override fails
            let vk = CGKeyCode(kVK_Space)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false) else {
                continue
            }

            // Override with our actual text
            keyDown.keyboardSetUnicodeString(stringLength: len, unicodeString: &chars)
            // Clear all modifier flags so held Fn/Shift/etc. don't interfere
            keyDown.flags = []
            keyUp.flags = []

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
