// Yappie/TranscriptionBackend.swift
import Foundation

protocol TranscriptionBackend {
    func transcribe(wavData: Data) async throws -> String
}

struct TranscriptionResult {
    let text: String
    let backendIndex: Int
}

final class BackendManager {
    private let backends: [TranscriptionBackend]
    let localModelLoadTime: TimeInterval?

    init(backends: [TranscriptionBackend], localModelLoadTime: TimeInterval? = nil) {
        self.backends = backends
        self.localModelLoadTime = localModelLoadTime
    }

    static func create(store: BackendStore) async -> BackendManager {
        debugLog("[Yappie] BackendManager.create: \(store.backends.count) backends configured")
        var enabledBackends: [TranscriptionBackend] = []
        var loadTime: TimeInterval?
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
                    do {
                        debugLog("[Yappie] Loading WhisperKit model...")
                        let backend = try await LocalBackend(
                            modelFolder: modelPath,
                            language: config.language
                        )
                        enabledBackends.append(backend)
                        loadTime = backend.loadDuration
                        debugLog("[Yappie] WhisperKit model loaded successfully")
                    } catch {
                        debugLog("[Yappie] WhisperKit model FAILED to load: \(error)")
                    }
                }
            }
        }
        debugLog("[Yappie] BackendManager created with \(enabledBackends.count) active backends")
        return BackendManager(backends: enabledBackends, localModelLoadTime: loadTime)
    }

    func transcribe(wavData: Data) async throws -> TranscriptionResult {
        guard !backends.isEmpty else {
            throw TranscriptionError.allBackendsFailed
        }

        for (index, backend) in backends.enumerated() {
            do {
                let text = try await backend.transcribe(wavData: wavData)
                return TranscriptionResult(text: text, backendIndex: index)
            } catch {
                debugLog("[Yappie] Backend \(index) failed: \(error)")
                continue
            }
        }

        throw TranscriptionError.allBackendsFailed
    }
}
