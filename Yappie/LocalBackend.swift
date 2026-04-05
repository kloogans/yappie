// Yappie/LocalBackend.swift
import Foundation
import WhisperKit

final class LocalBackend: TranscriptionBackend {
    private let pipe: WhisperKit
    private let language: String?

    init(modelFolder: String, language: String?) async throws {
        debugLog("[Yappie] WhisperKit init starting for: \(modelFolder)")
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            verbose: true,
            logLevel: .debug,
            prewarm: true,
            load: true,
            download: false
        )
        self.pipe = try await WhisperKit(config)
        self.language = language
        debugLog("[Yappie] WhisperKit init complete")
    }

    func transcribe(wavData: Data) async throws -> String {
        let lang = language ?? "en"
        debugLog("[Yappie DEBUG] LocalBackend.transcribe: \(wavData.count) bytes, language=\(lang)")
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try wavData.write(to: tempURL)
        // Save a debug copy
        let debugCopy = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/yappie-debug.wav")
        try? wavData.write(to: debugCopy)
        debugLog("[Yappie DEBUG] Wrote temp WAV to \(tempURL.path)")
        debugLog("[Yappie DEBUG] Debug copy saved to ~/Desktop/yappie-debug.wav")

        let options = DecodingOptions(
            task: .transcribe,
            language: lang,
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
