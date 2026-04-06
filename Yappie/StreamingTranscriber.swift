// Yappie/StreamingTranscriber.swift
import Foundation
import WhisperKit

final class StreamingTranscriber: @unchecked Sendable {
    private let pipe: WhisperKit
    private let language: String?
    private var streamTranscriber: AudioStreamTranscriber?
    private let lock = NSLock()
    private var lastDeliveredText = ""
    private var lastPurgeTime: TimeInterval = 0
    var onTextConfirmed: (@Sendable (String) -> Void)?

    // Keep 10 seconds of audio context for the model to work with
    private let audioContextSeconds: Double = 10
    // Purge audio every 15 seconds to prevent buffer from growing unbounded
    private let purgeIntervalSeconds: TimeInterval = 15

    init(pipe: WhisperKit, language: String?) {
        self.pipe = pipe
        self.language = language
    }

    func start() async throws {
        guard let tokenizer = pipe.tokenizer else {
            throw TranscriptionError.connectionFailed("WhisperKit tokenizer not available")
        }

        lock.lock()
        lastDeliveredText = ""
        lastPurgeTime = CFAbsoluteTimeGetCurrent()
        lock.unlock()

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: pipe.audioEncoder,
            featureExtractor: pipe.featureExtractor,
            segmentSeeker: pipe.segmentSeeker,
            textDecoder: pipe.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: pipe.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: 1,
            silenceThreshold: 0.3,
            useVAD: true
        ) { [weak self] _, newState in
            self?.handleStateChange(newState)
        }

        self.streamTranscriber = transcriber
        debugLog("[Yappie] StreamingTranscriber starting...")
        try await transcriber.startStreamTranscription()
    }

    func stop() async {
        guard let transcriber = streamTranscriber else { return }
        await transcriber.stopStreamTranscription()
        streamTranscriber = nil

        lock.lock()
        lastDeliveredText = ""
        lock.unlock()
        debugLog("[Yappie] StreamingTranscriber stopped")
    }

    private func handleStateChange(_ newState: AudioStreamTranscriber.State) {
        let allSegments = newState.confirmedSegments + newState.unconfirmedSegments
        let fullText = allSegments
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        guard fullText.count > lastDeliveredText.count else {
            lock.unlock()
            maybePurgeAudio()
            return
        }

        let newText = String(fullText.dropFirst(lastDeliveredText.count))
            .trimmingCharacters(in: .whitespaces)
        lastDeliveredText = fullText
        lock.unlock()

        guard !newText.isEmpty else {
            maybePurgeAudio()
            return
        }

        debugLog("[Yappie] Streaming: '\(newText)'")
        onTextConfirmed?(newText)
        maybePurgeAudio()
    }

    private func maybePurgeAudio() {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let elapsed = now - lastPurgeTime
        lock.unlock()

        guard elapsed >= purgeIntervalSeconds else { return }

        let keepSamples = Int(audioContextSeconds * Double(WhisperKit.sampleRate))
        pipe.audioProcessor.purgeAudioSamples(keepingLast: keepSamples)

        lock.lock()
        lastPurgeTime = now
        lock.unlock()
        debugLog("[Yappie] Purged audio buffer, keeping last \(Int(audioContextSeconds))s")
    }
}
