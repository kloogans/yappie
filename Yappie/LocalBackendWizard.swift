// Yappie/LocalBackendWizard.swift
import SwiftUI

// MARK: - Languages

private let supportedLanguages: [(code: String?, name: String)] = [
    (nil, "Auto-detect"),
    ("en", "English"),
    ("es", "Spanish"),
    ("fr", "French"),
    ("de", "German"),
    ("ja", "Japanese"),
    ("zh", "Chinese"),
    ("ko", "Korean"),
    ("pt", "Portuguese"),
    ("it", "Italian"),
    ("nl", "Dutch"),
]

// MARK: - Model Selection

struct LocalModelSelectionView: View {
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var onDismiss: () -> Void
    var onBack: () -> Void

    @State private var selectedVariant: String?
    @State private var selectedLanguage: String? = "en"
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var allModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showDownload = false

    private let recommendedVariant = LocalModelManager.recommendedVariant

    var body: some View {
        if showDownload, let variant = selectedVariant {
            LocalModelDownloadView(
                variant: variant,
                displayName: LocalModelManager.displayName(for: variant),
                sizeDescription: LocalModelManager.sizeDescription(for: variant),
                language: selectedLanguage,
                store: store,
                existingBackend: existingBackend,
                onDismiss: onDismiss,
                onBack: { showDownload = false }
            )
        } else {
            modelSelectionContent
        }
    }

    private var modelSelectionContent: some View {
        VStack(spacing: 0) {
            Text("Choose a Model")
                .font(.headline)
                .padding(.top)
            Text("Larger models are more accurate but use more memory and disk space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Language picker
            HStack(spacing: 8) {
                Text("Language")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedLanguage) {
                    ForEach(supportedLanguages, id: \.name) { lang in
                        Text(lang.name).tag(lang.code as String?)
                    }
                }
                .frame(width: 140)
                if selectedLanguage == nil {
                    Text("Setting a language improves speed & accuracy")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    // Curated models
                    ForEach(LocalModelManager.curatedModels, id: \.variant) { model in
                        let isRecommended = model.variant == recommendedVariant
                        let isSelected = selectedVariant == model.variant
                        CuratedModelCard(
                            model: model,
                            isRecommended: isRecommended,
                            isSelected: isSelected
                        ) {
                            selectedVariant = model.variant
                        }
                    }

                    // Browse all models
                    if !showSearch {
                        Button("Browse all models...") {
                            showSearch = true
                            if allModels.isEmpty {
                                loadAllModels()
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        modelSearchView
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            Divider()

            // Footer
            HStack {
                Text("Models stored in ~/Library/Application Support/Yappie/Models/")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("Back") { onBack() }
                Button("Download & Add") {
                    showDownload = true
                }
                .disabled(selectedVariant == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private var modelSearchView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(6)

            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            } else {
                let filtered = allModels.filter {
                    searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText)
                }
                ForEach(filtered.prefix(12), id: \.self) { model in
                    let isSelected = selectedVariant == model
                    Button {
                        selectedVariant = model
                    } label: {
                        HStack {
                            Text(model)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.green.opacity(0.1) : Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSelected ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if filtered.count > 12 {
                    Text("Showing 12 of \(filtered.count) matches")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func loadAllModels() {
        isLoadingModels = true
        Task {
            do {
                let models = try await LocalModelManager.availableModels()
                await MainActor.run {
                    allModels = models
                    isLoadingModels = false
                }
            } catch {
                debugLog("[Yappie] Failed to fetch model list: \(error)")
                await MainActor.run {
                    isLoadingModels = false
                }
            }
        }
    }

}

// MARK: - Curated Model Card

private struct CuratedModelCard: View {
    let model: CuratedModel
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .fontWeight(.semibold)
                            .font(.system(size: 13))
                        Text(model.sizeDescription)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .cornerRadius(3)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    Text(model.description)
                        .font(.system(size: 11))
                        .foregroundStyle(isRecommended ? .green : .secondary)
                }

                Spacer()

                // Accuracy bars
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bar <= model.accuracyBars ? Color.green : Color.primary.opacity(0.15))
                            .frame(width: 4, height: 10)
                    }
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isRecommended
                        ? Color.green.opacity(isSelected ? 0.12 : 0.06)
                        : (isSelected ? Color.green.opacity(0.06) : Color.primary.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.green.opacity(0.4) :
                        (isRecommended ? Color.green.opacity(0.2) : Color.primary.opacity(0.08)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Download Progress

struct LocalModelDownloadView: View {
    let variant: String
    let displayName: String
    let sizeDescription: String
    let language: String?
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var onDismiss: () -> Void
    var onBack: () -> Void

    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isComplete = false
    @State private var error: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var actualSize: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if isComplete {
                completeView
            } else if let error {
                errorView(error)
            } else {
                downloadingView
            }

            Spacer()
        }
        .onAppear { startDownload() }
        .onDisappear { downloadTask?.cancel() }
    }

    private var downloadingView: some View {
        VStack(spacing: 16) {
            Image("YappieTongue")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: Color(red: 0.96, green: 0.76, blue: 0.26).opacity(0.3), radius: 8, y: 2)

            Text("Downloading \(displayName)")
                .font(.system(size: 15, weight: .semibold))
            Text("\(sizeDescription) from Hugging Face")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ProgressView(value: downloadProgress)
                    .tint(.green)

                HStack {
                    Text(progressDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)

            Button("Cancel") {
                downloadTask?.cancel()
                onBack()
            }
            .padding(.top, 12)
        }
    }

    private var completeView: some View {
        VStack(spacing: 16) {
            Image("YappieSunglasses")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: Color(red: 0.96, green: 0.76, blue: 0.26).opacity(0.3), radius: 8, y: 2)

            Text("Ready to Go")
                .font(.system(size: 15, weight: .semibold))
            Text("\(displayName) downloaded successfully")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Summary card
            VStack(spacing: 6) {
                summaryRow(label: "Model", value: displayName)
                summaryRow(label: "Language", value: language.flatMap { code in
                    supportedLanguages.first { $0.code == code }?.name
                } ?? "Auto-detect")
                summaryRow(label: "Disk usage", value: actualSize ?? sizeDescription)
            }
            .padding(12)
            .background(.quaternary)
            .cornerRadius(8)
            .padding(.horizontal, 40)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The first time the model loads, macOS needs to optimize it for your hardware. This can take a few minutes but only happens once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)

            Button("Done") {
                if var existing = existingBackend {
                    existing.model = variant
                    existing.language = language
                    store.update(existing)
                } else {
                    let config = BackendConfig(
                        name: "Local Whisper",
                        type: .local,
                        enabled: true,
                        model: variant,
                        language: language
                    )
                    store.add(config)
                }
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Download Failed")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button("Back") { onBack() }
                Button("Retry") { startDownload() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private var progressDescription: String {
        guard let curated = LocalModelManager.curatedModels.first(where: { $0.variant == variant }) else {
            return "Downloading..."
        }
        let downloaded = Int64(downloadProgress * Double(curated.sizeBytes))
        return "\(LocalModelManager.byteFormatter.string(fromByteCount: downloaded)) of \(sizeDescription)"
    }

    private func startDownload() {
        error = nil
        isComplete = false
        downloadProgress = 0
        isDownloading = true

        downloadTask = Task {
            do {
                _ = try await LocalModelManager.download(variant: variant) { progress in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }

                await MainActor.run {
                    actualSize = LocalModelManager.modelSizeOnDisk(variant: variant)
                    isComplete = true
                    isDownloading = false
                }
            } catch is CancellationError {
                try? LocalModelManager.deleteModel(variant: variant)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}
