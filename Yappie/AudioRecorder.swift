// Yappie/AudioRecorder.swift
import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var pcmData = Data()
    private let sampleRate: Double = 16000
    private var converter: AVAudioConverter?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    var isRecording: Bool { engine.isRunning }

    func startRecording() throws {
        pcmData = Data()

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let wav = WAVEncoder.encode(pcmData: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        pcmData = Data()
        return wav
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        guard error == nil, let channelData = outputBuffer.int16ChannelData else { return }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        pcmData.append(Data(bytes: channelData[0], count: byteCount))
    }

    enum RecorderError: Error {
        case converterCreationFailed
    }
}
