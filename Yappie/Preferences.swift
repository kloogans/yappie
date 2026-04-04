// Yappie/Preferences.swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("serverHost") private var serverHost = "192.168.4.24"
    @AppStorage("serverPort") private var serverPort = 9876
    @AppStorage("recordingMode") private var recordingMode = RecordingMode.pushToTalk.rawValue
    @AppStorage("deliveryMode") private var deliveryMode = DeliveryMode.clipboardAndPaste.rawValue

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            serverTab
                .tabItem { Label("Server", systemImage: "network") }
        }
        .frame(width: 400, height: 220)
    }

    private var generalTab: some View {
        Form {
            Picker("Recording mode", selection: $recordingMode) {
                Text("Push-to-Talk (hold Fn)").tag(RecordingMode.pushToTalk.rawValue)
                Text("Toggle (click menubar)").tag(RecordingMode.toggle.rawValue)
            }
            .pickerStyle(.radioGroup)

            Picker("After transcription", selection: $deliveryMode) {
                Text("Copy & paste").tag(DeliveryMode.clipboardAndPaste.rawValue)
                Text("Copy to clipboard only").tag(DeliveryMode.clipboardOnly.rawValue)
            }
            .pickerStyle(.radioGroup)

            Toggle("Launch at login", isOn: launchAtLoginBinding)
        }
        .padding()
    }

    private var serverTab: some View {
        Form {
            TextField("Host", text: $serverHost)
            TextField("Port", value: $serverPort, format: .number)
        }
        .padding()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Launch at login failed: \(error)")
                }
            }
        )
    }
}
