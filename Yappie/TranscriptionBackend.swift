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

    init(backends: [TranscriptionBackend]) {
        self.backends = backends
    }

    static func create(store: BackendStore) async -> BackendManager {
        var enabledBackends: [TranscriptionBackend] = []
        for config in store.backends where config.enabled {
            switch config.type {
            case .api:
                enabledBackends.append(APIBackend(config: config))
            case .tcp:
                enabledBackends.append(TCPBackend(config: config))
            case .local:
                if let modelPath = LocalModelManager.downloadedModelDirectoryPath() {
                    do {
                        let backend = try await LocalBackend(
                            modelFolder: modelPath,
                            language: config.language
                        )
                        enabledBackends.append(backend)
                    } catch {
                        NSLog("[Yappie] Failed to load local model: %@", "\(error)")
                    }
                }
            }
        }
        return BackendManager(backends: enabledBackends)
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
                NSLog("[Yappie] Backend %d failed: %@", index, "\(error)")
                continue
            }
        }

        throw TranscriptionError.allBackendsFailed
    }
}
