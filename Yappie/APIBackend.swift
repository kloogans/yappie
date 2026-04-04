// Yappie/APIBackend.swift
import Foundation

final class APIBackend: TranscriptionBackend {
    private let config: BackendConfig
    private let apiKey: String?
    private static let decoder = JSONDecoder()

    init(config: BackendConfig) {
        self.config = config
        self.apiKey = KeychainHelper.get(forBackendID: config.id)
    }

    func transcribe(wavData: Data) async throws -> String {
        let request = try Self.buildRequest(config: config, wavData: wavData, apiKey: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let text = try Self.parseResponse(data: data)
        guard !text.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        return text
    }

    static func buildRequest(config: BackendConfig, wavData: Data, apiKey: String?) throws -> URLRequest {
        guard let baseURL = config.baseURL,
              let url = URL(string: baseURL)?.appendingPathComponent("audio/transcriptions") else {
            throw TranscriptionError.connectionFailed("Invalid base URL")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = buildMultipartBody(wavData: wavData, model: config.model, boundary: boundary)
        return request
    }

    static func buildMultipartBody(wavData: Data, model: String?, boundary: String) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        if let model, !model.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func parseResponse(data: Data) throws -> String {
        if let json = try? Self.decoder.decode(WhisperResponse.self, from: data) {
            return json.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WhisperResponse: Decodable {
    let text: String
}
