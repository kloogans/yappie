// Yappie/BackendWizard.swift
import SwiftUI

// MARK: - Add Wizard (Two-Step)

struct BackendWizardView: View {
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: BackendType?

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Backend")
                .font(.headline)
                .padding()

            if let selectedType {
                BackendFormView(
                    type: selectedType,
                    store: store,
                    onDismiss: { dismiss() },
                    onBack: { self.selectedType = nil }
                )
            } else {
                typeSelectionView
            }
        }
        .frame(width: 420, height: 360)
    }

    private var typeSelectionView: some View {
        VStack(spacing: 12) {
            TypeSelectionButton(
                emoji: "\u{1F310}",
                title: "OpenAI-Compatible API",
                subtitle: "Works with OpenAI, Groq, Together AI, local servers like faster-whisper-server, and any service implementing the Whisper API."
            ) {
                selectedType = .api
            }

            TypeSelectionButton(
                emoji: "\u{1F50C}",
                title: "Custom TCP Socket",
                subtitle: "Direct TCP connection \u{2014} send WAV audio, receive text. For custom transcription servers on your network."
            ) {
                selectedType = .tcp
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
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
            HStack(spacing: 12) {
                Text(emoji).font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.quaternary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backend Form (shared by Add and Edit)

struct BackendFormView: View {
    let type: BackendType
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var onDismiss: () -> Void
    var onBack: (() -> Void)?

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var host: String = ""
    @State private var port: String = ""

    init(type: BackendType, store: BackendStore, existingBackend: BackendConfig? = nil, onDismiss: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.type = type
        self.store = store
        self.existingBackend = existingBackend
        self.onDismiss = onDismiss
        self.onBack = onBack

        if let existing = existingBackend {
            _name = State(initialValue: existing.name)
            _baseURL = State(initialValue: existing.baseURL ?? "")
            _model = State(initialValue: existing.model ?? "")
            _host = State(initialValue: existing.host ?? "")
            _port = State(initialValue: existing.port.map { String($0) } ?? "")
            _apiKey = State(initialValue: KeychainHelper.get(forBackendID: existing.id) ?? "")
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
