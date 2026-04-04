// Yappie/HotkeyRecorderView.swift
import SwiftUI
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.keyCode = keyCode
        view.modifiers = modifiers
        view.onChange = { code, mods in
            keyCode = code
            modifiers = mods
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        if nsView.keyCode != keyCode || nsView.modifiers != modifiers {
            nsView.keyCode = keyCode
            nsView.modifiers = modifiers
            nsView.needsDisplay = true
        }
    }
}

class HotkeyRecorderNSView: NSView {
    fileprivate var keyCode: Int = -1
    fileprivate var modifiers: Int = 0
    fileprivate var onChange: ((Int, Int) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press a key combo..."
        } else if keyCode == -1 {
            text = "Fn (default)"
        } else {
            text = HotkeyManager.displayName(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        str.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let carbonMods = HotkeyManager.carbonModifiers(from: event.modifierFlags)

        // Escape cancels recording
        if event.keyCode == 0x35 {
            endRecording()
            return
        }

        keyCode = Int(event.keyCode)
        modifiers = Int(carbonMods)
        endRecording()
        onChange?(keyCode, modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    private func endRecording() {
        isRecording = false
        needsDisplay = true
    }
}
