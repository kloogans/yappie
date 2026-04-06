// Yappie/LocalBackend.swift
import Foundation
import WhisperKit

final class LocalBackend: TranscriptionBackend {
    private let pipe: WhisperKit
    private let language: String?
    let loadDuration: TimeInterval

    init(modelFolder: String, language: String?) async throws {
        debugLog("[Yappie] WhisperKit init starting for: \(modelFolder)")
        let startTime = CFAbsoluteTimeGetCurrent()
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        self.pipe = try await WhisperKit(config)
        self.language = language
        self.loadDuration = CFAbsoluteTimeGetCurrent() - startTime
        debugLog("[Yappie] WhisperKit init complete (\(String(format: "%.1f", loadDuration))s)")
    }

    func transcribe(wavData: Data) async throws -> String {
        debugLog("[Yappie] LocalBackend.transcribe: \(wavData.count) bytes, language=\(language ?? "auto")")
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try wavData.write(to: tempURL)

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await pipe.transcribe(
            audioPath: tempURL.path,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw TranscriptionError.emptyResponse
        }

        return text
    }
}
