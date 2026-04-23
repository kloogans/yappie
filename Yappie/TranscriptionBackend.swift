// Yappie/TranscriptionBackend.swift
import Foundation

protocol TranscriptionBackend {
    func transcribe(audioSamples: [Float]) async throws -> String
}

struct TranscriptionResult {
    let text: String
    let backendIndex: Int
}

/// Wraps a local backend config and loads the model on first transcription call.
actor LazyLocalBackend: TranscriptionBackend {
    private let modelPath: String
    private let language: String?
    private var loaded: LocalBackend?

    init(modelPath: String, language: String?) {
        self.modelPath = modelPath
        self.language = language
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        if loaded == nil {
            debugLog("[Yappie] Lazy-loading fallback model: \(modelPath)")
            loaded = try await LocalBackend(modelFolder: modelPath, language: language)
            debugLog("[Yappie] Fallback model loaded (\(String(format: "%.1f", loaded!.loadDuration))s)")
        }
        return try await loaded!.transcribe(audioSamples: audioSamples)
    }
}

final class BackendManager {
    private let backends: [TranscriptionBackend]
    let localModelLoadTime: TimeInterval?

    init(backends: [TranscriptionBackend], localModelLoadTime: TimeInterval? = nil) {
        self.backends = backends
        self.localModelLoadTime = localModelLoadTime
    }

    static func create(store: BackendStore, onBackendLoaded: (@MainActor (UUID) -> Void)? = nil) async -> BackendManager {
        debugLog("[Yappie] BackendManager.create: \(store.backends.count) backends configured")
        var enabledBackends: [TranscriptionBackend] = []
        var loadTime: TimeInterval?
        var primaryLocalLoaded = false
        for config in store.backends where config.enabled {
            debugLog("[Yappie] Processing backend [\(enabledBackends.count)]: \(config.name) type=\(config.type.rawValue) model=\(config.model ?? "none")")
            switch config.type {
            case .api:
                enabledBackends.append(APIBackend(config: config))
            case .tcp:
                enabledBackends.append(TCPBackend(config: config))
            case .local:
                let modelPath = config.model.flatMap { LocalModelManager.modelDirectoryPath(for: $0) }
                debugLog("[Yappie] Local model path: \(modelPath ?? "nil")")
                if let modelPath {
                    if !primaryLocalLoaded {
                        // Eagerly load the first (primary) local backend
                        do {
                            debugLog("[Yappie] Loading primary WhisperKit model...")
                            let language = config.language
                            let backend = try await Task.detached {
                                try await LocalBackend(modelFolder: modelPath, language: language)
                            }.value
                            enabledBackends.append(backend)
                            loadTime = backend.loadDuration
                            primaryLocalLoaded = true
                            debugLog("[Yappie] Primary model loaded successfully")
                            await onBackendLoaded?(config.id)
                        } catch {
                            debugLog("[Yappie] Primary model FAILED to load: \(error)")
                            await onBackendLoaded?(config.id)
                        }
                    } else {
                        // Defer fallback local backends to load on first use
                        debugLog("[Yappie] Deferring fallback model: \(config.model ?? "unknown")")
                        enabledBackends.append(LazyLocalBackend(modelPath: modelPath, language: config.language))
                    }
                }
            }
        }
        debugLog("[Yappie] BackendManager created with \(enabledBackends.count) active backends (\(primaryLocalLoaded ? "primary loaded" : "no local"))")
        return BackendManager(backends: enabledBackends, localModelLoadTime: loadTime)
    }

    func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        guard !backends.isEmpty else {
            throw TranscriptionError.allBackendsFailed
        }

        var allReturnedEmpty = true

        for (index, backend) in backends.enumerated() {
            do {
                let text = try await backend.transcribe(audioSamples: audioSamples)
                return TranscriptionResult(text: text, backendIndex: index)
            } catch TranscriptionError.emptyResponse {
                debugLog("[Yappie] Backend \(index) returned empty transcription")
                continue
            } catch {
                debugLog("[Yappie] Backend \(index) failed: \(error)")
                allReturnedEmpty = false
                continue
            }
        }

        throw allReturnedEmpty ? TranscriptionError.emptyResponse : TranscriptionError.allBackendsFailed
    }
}
