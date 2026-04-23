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

    func transcribe(audioSamples: [Float]) async throws -> String {
        debugLog("[Yappie] LocalBackend.transcribe: \(audioSamples.count) samples, language=\(language ?? "auto")")

        // Whisper (especially the small/tiny models) often returns empty text for
        // clips under ~1s at temperature 0. Prepend silence so brief utterances
        // sit further into the 30s decode window Whisper builds internally.
        let minSamples = 16000 // 1s at 16kHz
        let padded: [Float]
        if audioSamples.count < minSamples {
            padded = [Float](repeating: 0, count: minSamples - audioSamples.count) + audioSamples
        } else {
            padded = audioSamples
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await pipe.transcribe(
            audioArray: padded,
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
