// Yappie/YappieApp.swift
import SwiftUI
import AVFoundation

@main
struct YappieApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Yappie", systemImage: appState.statusIcon) {
            Button("Toggle Recording") {
                appState.toggleRecording()
            }

            Divider()

            Button("Preferences…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            PreferencesView()
                .environmentObject(appState)
        }
    }

    init() {
        // Request mic permission — triggers system dialog on first launch
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[Yappie] Mic permission granted: %@", granted ? "yes" : "no")
            }
        case .denied, .restricted:
            NSLog("[Yappie] Mic permission denied — user must enable in System Settings")
        case .authorized:
            NSLog("[Yappie] Mic permission already granted")
        @unknown default:
            break
        }
        _ = TextDelivery.checkAccessibility(prompt: true)
    }
}
