// Yappie/YappieApp.swift
import SwiftUI
import AVFoundation

@main
struct YappieApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var prefsWindowController = PreferencesWindowController()

    var body: some Scene {
        MenuBarExtra("Yappie", image: "MenuBarIcon") {
            switch appState.modelLoadingStatus {
            case .loading:
                Text("Preparing model…")
                    .foregroundStyle(.secondary)
                Divider()
            case .failed:
                Text("Model failed to load")
                    .foregroundStyle(.red)
                Button("Open Preferences…") {
                    prefsWindowController.appState = appState
                    prefsWindowController.show()
                }
                Divider()
            case .idle, .ready:
                EmptyView()
            }

            Button("Toggle Recording") {
                appState.toggleRecording()
            }
            .disabled(appState.modelLoadingStatus == .loading)

            Divider()

            Button("Preferences…") {
                prefsWindowController.appState = appState
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
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                debugLog("[Yappie] Mic permission granted")
            } else {
                debugLog("[Yappie] Mic permission denied. Enable in System Settings.")
            }
        }
        _ = TextDelivery.checkAccessibility(prompt: true)
    }
}

final class PreferencesWindowController: ObservableObject {
    private var window: NSWindow?
    var appState: AppState?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let appState else { return }
        let prefsView = PreferencesView(appState: appState)
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
