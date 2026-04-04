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

    // MARK: - Push-to-Talk (Fn key)

    func startFnMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed && !self.fnIsDown {
                self.fnIsDown = true
                DispatchQueue.main.async { self.onRecordStart?() }
            } else if !fnPressed && self.fnIsDown {
                self.fnIsDown = false
                DispatchQueue.main.async { self.onRecordStop?() }
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

    // MARK: - Toggle Hotkey (Carbon)

    private var isToggled = false

    func registerToggleHotkey(keyCode: UInt32, modifiers: UInt32) {
        unregisterToggleHotkey()

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x59415050), // "YAPP"
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, event, refcon -> OSStatus in
            guard let refcon else { return OSStatus(eventNotHandledErr) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                if mgr.isToggled {
                    mgr.isToggled = false
                    mgr.onRecordStop?()
                } else {
                    mgr.isToggled = true
                    mgr.onRecordStart?()
                }
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, refcon, &handlerRef)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregisterToggleHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        isToggled = false
    }

    deinit {
        stopFnMonitor()
        unregisterToggleHotkey()
    }
}
