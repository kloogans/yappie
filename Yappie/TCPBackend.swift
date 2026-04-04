// Yappie/TCPBackend.swift
import Foundation
import Network

enum TranscriptionError: Error, Equatable {
    case connectionFailed(String)
    case serverError(String)
    case emptyResponse
    case allBackendsFailed
}

final class TCPBackend: TranscriptionBackend {
    private let host: String
    private let port: UInt16
    private static let queue = DispatchQueue(label: "yappie.tcp")

    init(config: BackendConfig) {
        self.host = config.host ?? "127.0.0.1"
        self.port = UInt16(config.port ?? 9876)
    }

    func transcribe(wavData: Data) async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            func resume(with result: Result<String, Error>) {
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                hasResumed = true
                lock.unlock()
                switch result {
                case .success(let text): continuation.resume(returning: text)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                default:
                    break
                }
            }

            connection.start(queue: Self.queue)

            connection.send(content: wavData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                    return
                }

                self.readAll(connection) { data in
                    connection.cancel()

                    guard let data, !data.isEmpty else {
                        resume(with: .failure(TranscriptionError.emptyResponse))
                        return
                    }

                    guard let text = String(data: data, encoding: .utf8) else {
                        resume(with: .failure(TranscriptionError.emptyResponse))
                        return
                    }

                    if text.hasPrefix("ERROR:") {
                        let msg = String(text.dropFirst(6))
                        resume(with: .failure(TranscriptionError.serverError(msg)))
                    } else {
                        resume(with: .success(text))
                    }
                }
            })
        }
    }

    private func readAll(_ connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var acc = accumulated
            if let data { acc.append(data) }
            if isComplete || error != nil {
                completion(acc)
            } else {
                self.readAll(connection, accumulated: acc, completion: completion)
            }
        }
    }
}
