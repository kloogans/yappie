// Yappie/Preferences.swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("recordingMode") private var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") private var deliveryMode: DeliveryMode = .clipboardAndPaste
    @ObservedObject var backendStore: BackendStore

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            backendsTab
                .tabItem { Label("Backends", systemImage: "server.rack") }
        }
        .frame(width: 500, height: 380)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Picker("Recording mode", selection: $recordingMode) {
                Text("Push-to-Talk (hold Fn)").tag(RecordingMode.pushToTalk)
                Text("Toggle (click menubar)").tag(RecordingMode.toggle)
            }
            .pickerStyle(.radioGroup)

            Picker("After transcription", selection: $deliveryMode) {
                Text("Copy & paste").tag(DeliveryMode.clipboardAndPaste)
                Text("Copy to clipboard only").tag(DeliveryMode.clipboardOnly)
            }
            .pickerStyle(.radioGroup)

            Toggle("Launch at login", isOn: launchAtLoginBinding)
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
                    NSLog("[Yappie] Launch at login failed: %@", "\(error)")
                }
            }
        )
    }

    // MARK: - Backends Tab

    @State private var showAddWizard = false

    private var backendsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Backends")
                .font(.headline)
                .padding(.horizontal)

            Text("Backends are tried in order. If the first fails, the next one is used automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(backendStore.backends) { backend in
                    BackendCardView(backend: backend, store: backendStore)
                }
                .onMove { source, dest in
                    backendStore.move(from: source, to: dest)
                }
            }
            .listStyle(.plain)

            HStack {
                Spacer()
                Button("Add Backend\u{2026}") {
                    showAddWizard = true
                }
                Spacer()
            }
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAddWizard) {
            // BackendWizardView will be added in Task 7
            // For now, show a placeholder
            VStack {
                Text("Add Backend Wizard")
                    .font(.headline)
                Text("Coming in next task")
                    .foregroundStyle(.secondary)
                Button("Close") { showAddWizard = false }
                    .padding()
            }
            .frame(width: 400, height: 300)
        }
    }
}

// MARK: - Backend Card

struct BackendCardView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(backend.name)
                        .fontWeight(.medium)
                    priorityBadge
                }
                HStack(spacing: 6) {
                    Text(backend.type == .api ? "API" : "TCP")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(3)
                    Text(connectionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { backend.enabled },
                set: { newValue in
                    var updated = backend
                    updated.enabled = newValue
                    store.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", role: .destructive) {
                if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
                    store.remove(at: index)
                }
            }
        }
    }

    private var connectionDetail: String {
        switch backend.type {
        case .api:
            let url = backend.baseURL ?? ""
            let model = backend.model.map { " \u{00B7} \($0)" } ?? ""
            let key = KeychainHelper.get(forBackendID: backend.id) != nil ? " \u{00B7} \u{2022}\u{2022}\u{2022}\u{2022}" : ""
            return "\(url)\(model)\(key)"
        case .tcp:
            return "\(backend.host ?? ""):\(backend.port ?? 0)"
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        let enabledBackends = store.backends.filter { $0.enabled }
        let position = enabledBackends.firstIndex(where: { $0.id == backend.id })

        if let position, backend.enabled {
            Text(position == 0 ? "PRIMARY" : "FALLBACK")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(position == 0 ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(3)
        }
    }
}
