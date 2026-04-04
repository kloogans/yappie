// Yappie/HotkeyManager.swift
import AppKit
import Carbon

final class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsDown = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isToggled = false

    // MARK: - Push-to-Talk (Fn key)

    func startFnMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed && !self.fnIsDown {
                self.fnIsDown = true
                self.onRecordStart?()
            } else if !fnPressed && self.fnIsDown {
                self.fnIsDown = false
                self.onRecordStop?()
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    func stopFnMonitor() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        fnIsDown = false
    }

    // MARK: - Custom Hotkey (Carbon)

    func registerHotkey(keyCode: UInt32, modifiers: UInt32, pushToTalk: Bool) {
        unregisterHotkey()

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x59415050), // "YAPP"
            id: 1
        )

        if pushToTalk {
            // Register for both key down and key up
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]

            let refcon = Unmanaged.passUnretained(self).toOpaque()

            let callback: EventHandlerUPP = { _, event, refcon -> OSStatus in
                guard let refcon, let event else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let eventKind = GetEventKind(event)

                if eventKind == UInt32(kEventHotKeyPressed) {
                    mgr.onRecordStart?()
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    mgr.onRecordStop?()
                }
                return noErr
            }

            InstallEventHandler(GetApplicationEventTarget(), callback, 2, &eventTypes, refcon, &handlerRef)
        } else {
            // Toggle mode: press to start, press again to stop
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let refcon = Unmanaged.passUnretained(self).toOpaque()

            let callback: EventHandlerUPP = { _, _, refcon -> OSStatus in
                guard let refcon else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                mgr.isToggled.toggle()
                if mgr.isToggled {
                    mgr.onRecordStart?()
                } else {
                    mgr.onRecordStop?()
                }
                return noErr
            }

            InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, refcon, &handlerRef)
        }

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        isToggled = false
    }

    deinit {
        stopFnMonitor()
        unregisterHotkey()
    }

    // MARK: - Key Display Name Helpers

    static func displayName(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = [String]()
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private static let keyNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x30: "Tab", 0x31: "Space", 0x33: "Delete",
        0x35: "Esc", 0x24: "Return",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
}
