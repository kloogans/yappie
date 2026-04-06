// Yappie/Preferences.swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("recordingMode") private var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") private var deliveryMode: DeliveryMode = .clipboardAndPaste
    @AppStorage("hotkeyCode") private var hotkeyCode: Int = -1
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0
    @ObservedObject var backendStore: BackendStore
    @State private var showAddWizard = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            backendsTab
                .tabItem { Label("Backends", systemImage: "server.rack") }
        }
        .frame(width: 520, height: 400)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Recording section
            VStack(alignment: .leading, spacing: 8) {
                Label("Recording", systemImage: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Recording mode", selection: $recordingMode) {
                    Text("Push-to-Talk (hold key)").tag(RecordingMode.pushToTalk)
                    Text("Toggle (press to start/stop)").tag(RecordingMode.toggle)
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Text("Hotkey")
                        .frame(width: 60, alignment: .trailing)
                    HotkeyRecorderView(
                        keyCode: $hotkeyCode,
                        modifiers: $hotkeyModifiers
                    )
                    if hotkeyCode != -1 {
                        Button("Reset to Fn") {
                            hotkeyCode = -1
                            hotkeyModifiers = 0
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 4)

                if hotkeyCode == -1 {
                    Text("Using Fn key. Click the field above to set a custom hotkey.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Output section
            VStack(alignment: .leading, spacing: 8) {
                Label("Output", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("After transcription", selection: $deliveryMode) {
                    Text("Copy & paste").tag(DeliveryMode.clipboardAndPaste)
                    Text("Copy to clipboard only").tag(DeliveryMode.clipboardOnly)
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            // System section
            VStack(alignment: .leading, spacing: 8) {
                Label("System", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }

            Spacer()
        }
        .padding(24)
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

    private var backendsTab: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription Backends")
                    .font(.headline)
                Text("Backends are tried in order. If the first fails, the next one is used automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Backend list or empty state
            if backendStore.backends.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No backends configured")
                        .foregroundStyle(.secondary)
                    Text("Add a backend to start transcribing.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    let enabledBackends = backendStore.enabledBackends
                    VStack(spacing: 8) {
                        ForEach(backendStore.backends) { backend in
                            let hasAPIKey = KeychainHelper.get(forBackendID: backend.id) != nil
                            let priorityLabel: String? = {
                                guard backend.enabled,
                                      let position = enabledBackends.firstIndex(where: { $0.id == backend.id })
                                else { return nil }
                                return position == enabledBackends.startIndex ? "PRIMARY" : "FALLBACK"
                            }()
                            BackendCardView(
                                backend: backend,
                                store: backendStore,
                                hasAPIKey: hasAPIKey,
                                priorityLabel: priorityLabel
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Add button
            Divider()
            HStack {
                Spacer()
                Button {
                    showAddWizard = true
                } label: {
                    Label("Add Backend", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(12)
                Spacer()
            }
        }
        .sheet(isPresented: $showAddWizard) {
            BackendWizardView(store: backendStore)
        }
    }
}

// MARK: - Backend Card

struct BackendCardView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore
    let hasAPIKey: Bool
    let priorityLabel: String?
    @State private var showEdit = false

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Group {
                if backend.type == .local {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: backend.type == .api ? "globe" : "network")
                        .font(.system(size: 16))
                        .foregroundStyle(backend.enabled ? .primary : .tertiary)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(backend.name)
                        .fontWeight(.medium)
                        .foregroundStyle(backend.enabled ? .primary : .secondary)
                    priorityBadge
                }
                Text(connectionDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                deleteBackend()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Toggle("", isOn: Binding(
                get: { backend.enabled },
                set: { newValue in
                    var updated = backend
                    updated.enabled = newValue
                    store.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backend.enabled ? Color.primary.opacity(0.04) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .onTapGesture(count: 2) {
            showEdit = true
        }
        .contextMenu {
            Button("Edit...") { showEdit = true }
            Divider()
            Button("Delete", role: .destructive) {
                deleteBackend()
            }
        }
        .sheet(isPresented: $showEdit) {
            BackendEditView(backend: backend, store: store)
        }
    }

    private func deleteBackend() {
        if backend.type == .local, let variant = backend.model {
            try? LocalModelManager.deleteModel(variant: variant)
        }
        if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
            store.remove(at: index)
        }
    }

    private var connectionDetail: String {
        switch backend.type {
        case .api:
            var parts = [String]()
            if let url = backend.baseURL, !url.isEmpty {
                if let parsed = URL(string: url) {
                    parts.append(parsed.host ?? url)
                } else {
                    parts.append(url)
                }
            }
            if let model = backend.model, !model.isEmpty {
                parts.append(model)
            }
            if hasAPIKey {
                parts.append("API key set")
            }
            return parts.joined(separator: " \u{00B7} ")
        case .tcp:
            return "\(backend.host ?? ""):\(backend.port ?? 0)"
        case .local:
            var parts = [String]()
            if let model = backend.model {
                let displayName = LocalModelManager.curatedModels.first { $0.variant == model }?.displayName ?? model
                parts.append(displayName)
            }
            parts.append(backend.language.flatMap { code in
                Locale.current.localizedString(forLanguageCode: code) ?? code
            } ?? "Auto-detect")
            if let model = backend.model, let size = LocalModelManager.modelSizeOnDisk(variant: model) {
                parts.append(size)
            }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        if let priorityLabel {
            Text(priorityLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(priorityLabel == "PRIMARY" ? Color.green : Color.gray.opacity(0.6))
                )
                .foregroundColor(.white)
        }
    }
}
