// Yappie/YappieApp.swift
import SwiftUI

@main
struct YappieApp: App {
    var body: some Scene {
        MenuBarExtra("Yappie", systemImage: "mic") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            Text("Preferences placeholder")
                .frame(width: 300, height: 200)
        }
    }
}
