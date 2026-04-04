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
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.connectAndTranscribe(wavData: wavData)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw TranscriptionError.connectionFailed("Connection timed out")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func connectAndTranscribe(wavData: Data) async throws -> String {
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
                connection.cancel()
                switch result {
                case .success(let text): continuation.resume(returning: text)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    resume(with: .failure(TranscriptionError.connectionFailed("Connection cancelled")))
                default:
                    break
                }
            }

            connection.start(queue: Self.queue)

            connection.send(content: wavData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                    return
                }

                self.readAll(connection) { data in
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
