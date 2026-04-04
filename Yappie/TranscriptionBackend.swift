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

    convenience init(store: BackendStore) {
        let enabledBackends: [TranscriptionBackend] = store.backends
            .filter { $0.enabled }
            .map { config in
                switch config.type {
                case .api: return APIBackend(config: config)
                case .tcp: return TCPBackend(config: config)
                }
            }
        self.init(backends: enabledBackends)
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
