// Yappie/YappieApp.swift
import SwiftUI
import AVFoundation

@main
struct YappieApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var prefsWindowController = PreferencesWindowController()

    var body: some Scene {
        MenuBarExtra("Yappie", systemImage: appState.statusIcon) {
            Button("Toggle Recording") {
                appState.toggleRecording()
            }

            Divider()

            Button("Preferences…") {
                prefsWindowController.backendStore = appState.backendStore
                prefsWindowController.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    init() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[Yappie] Mic permission granted: %@", granted ? "yes" : "no")
            }
        case .denied, .restricted:
            NSLog("[Yappie] Mic permission denied — user must enable in System Settings")
        case .authorized:
            break
        @unknown default:
            break
        }
        _ = TextDelivery.checkAccessibility(prompt: true)
    }
}

final class PreferencesWindowController: ObservableObject {
    private var window: NSWindow?
    var backendStore: BackendStore?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView(backendStore: backendStore ?? BackendStore())
        let hostingView = NSHostingView(rootView: prefsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 380)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yappie Preferences"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
