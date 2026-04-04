// Yappie/YappieApp.swift
import SwiftUI
import AVFoundation

@main
struct YappieApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Yappie", systemImage: appState.statusIcon) {
            Group {
                if appState.status == .recording {
                    Text("Recording… \(String(format: "%.1f", appState.recordingDuration))s")
                    Button("Stop") { appState.stopRecording() }
                } else if appState.status == .transcribing {
                    Text("Transcribing…")
                } else {
                    Button("Start Recording") { appState.startRecording() }
                }
            }

            Divider()

            SettingsLink {
                Text("Preferences…")
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
        Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        _ = TextDelivery.checkAccessibility(prompt: true)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
}
