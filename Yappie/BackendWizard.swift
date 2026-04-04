// Yappie/BackendWizard.swift
import SwiftUI

// MARK: - Presets

struct APIPreset {
    let name: String
    let baseURL: String
    let model: String
    let needsKey: Bool
    let icon: String
}

private let apiPresets: [APIPreset] = [
    APIPreset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "whisper-1", needsKey: true, icon: "brain"),
    APIPreset(name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo", needsKey: true, icon: "bolt.fill"),
    APIPreset(name: "faster-whisper-server", baseURL: "http://localhost:8000/v1", model: "large-v3-turbo", needsKey: false, icon: "server.rack"),
]

// MARK: - Add Wizard (Two-Step)

struct BackendWizardView: View {
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: BackendType?
    @State private var selectedPreset: APIPreset?

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Backend")
                .font(.headline)
                .padding()

            if let selectedType {
                BackendFormView(
                    type: selectedType,
                    store: store,
                    preset: selectedPreset,
                    onDismiss: { dismiss() },
                    onBack: { self.selectedType = nil; self.selectedPreset = nil }
                )
            } else {
                typeSelectionView
            }
        }
        .frame(width: 420, height: 420)
    }

    private var typeSelectionView: some View {
        VStack(spacing: 16) {
            // Quick presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Setup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                ForEach(apiPresets, id: \.name) { preset in
                    Button {
                        selectedPreset = preset
                        selectedType = .api
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .frame(width: 20)
                                .foregroundStyle(.primary)
                            Text(preset.name)
                                .fontWeight(.medium)
                            Spacer()
                            if preset.needsKey {
                                Text("API key required")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Custom options
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                TypeSelectionButton(
                    emoji: "\u{1F310}",
                    title: "Custom API Endpoint",
                    subtitle: "Any OpenAI-compatible Whisper API"
                ) {
                    selectedType = .api
                }

                TypeSelectionButton(
                    emoji: "\u{1F50C}",
                    title: "Custom TCP Socket",
                    subtitle: "Direct TCP connection for custom servers"
                ) {
                    selectedType = .tcp
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Type Selection Button

private struct TypeSelectionButton: View {
    let emoji: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji).font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(.medium)
                        .font(.system(size: 13))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backend Form (shared by Add and Edit)

struct BackendFormView: View {
    let type: BackendType
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var preset: APIPreset?
    var onDismiss: () -> Void
    var onBack: (() -> Void)?

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var host: String = ""
    @State private var port: String = ""

    init(type: BackendType, store: BackendStore, existingBackend: BackendConfig? = nil, preset: APIPreset? = nil, onDismiss: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.type = type
        self.store = store
        self.existingBackend = existingBackend
        self.preset = preset
        self.onDismiss = onDismiss
        self.onBack = onBack

        if let existing = existingBackend {
            _name = State(initialValue: existing.name)
            _baseURL = State(initialValue: existing.baseURL ?? "")
            _model = State(initialValue: existing.model ?? "")
            _host = State(initialValue: existing.host ?? "")
            _port = State(initialValue: existing.port.map { String($0) } ?? "")
            _apiKey = State(initialValue: KeychainHelper.get(forBackendID: existing.id) ?? "")
        } else if let preset {
            _name = State(initialValue: preset.name)
            _baseURL = State(initialValue: preset.baseURL)
            _model = State(initialValue: preset.model)
        }
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text(type == .api ? "e.g. OpenAI" : "e.g. Home Server"))

            if type == .api {
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("Optional for local servers"))
                TextField("Model", text: $model, prompt: Text("e.g. whisper-1 (optional)"))
            } else {
                TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                TextField("Port", text: $port, prompt: Text("9876"))
            }
        }
        .padding()

        Spacer()

        HStack {
            if let onBack {
                Button("Back") { onBack() }
            }
            Spacer()
            Button("Cancel") { onDismiss() }
            Button(existingBackend == nil ? "Add" : "Save") {
                save()
            }
            .disabled(name.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func save() {
        if var existing = existingBackend {
            existing.name = name
            existing.baseURL = type == .api ? baseURL : nil
            existing.model = type == .api && !model.isEmpty ? model : nil
            existing.host = type == .tcp ? host : nil
            existing.port = type == .tcp ? Int(port) : nil

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: existing.id)
            } else if type == .api && apiKey.isEmpty {
                KeychainHelper.delete(forBackendID: existing.id)
            }

            store.update(existing)
        } else {
            let config = BackendConfig(
                name: name,
                type: type,
                enabled: true,
                baseURL: type == .api ? baseURL : nil,
                model: type == .api && !model.isEmpty ? model : nil,
                host: type == .tcp ? host : nil,
                port: type == .tcp ? Int(port) : nil
            )

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: config.id)
            }

            store.add(config)
        }

        onDismiss()
    }
}

// MARK: - Edit View

struct BackendEditView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Backend")
                .font(.headline)
                .padding()

            BackendFormView(
                type: backend.type,
                store: store,
                existingBackend: backend,
                onDismiss: { dismiss() }
            )
        }
        .frame(width: 420, height: 300)
    }
}
