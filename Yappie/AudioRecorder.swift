// Yappie/AudioRecorder.swift
import AVFoundation
import CoreAudio

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var floatSamples = [Float]()
    private var hwSampleRate: Double = 44100
    private let targetSampleRate: Double = 16000

    private(set) var isRecording = false

    func startRecording() throws {
        floatSamples = []

        // Switch system default input to built-in mic (if available)
        // AVAudioEngine always uses the system default, so we must change it
        let originalDevice = Self.getDefaultInputDevice()
        if let builtInID = Self.findBuiltInMicID(), builtInID != originalDevice {
            Self.setDefaultInputDevice(builtInID)
            NSLog("[Yappie] Switched default input to built-in mic (ID: %d)", builtInID)
        }

        // Create a fresh engine each time (device binding is per-engine)
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        hwSampleRate = hwFormat.sampleRate

        NSLog("[Yappie] Recording format: %d ch, %.0f Hz", hwFormat.channelCount, hwFormat.sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            for i in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][i]
                }
                sample /= Float(channelCount)
                self.floatSamples.append(sample)
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        isRecording = true
    }

    func stopRecording() -> Data {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRecording = false

        // Downsample to 16kHz
        let ratio = hwSampleRate / targetSampleRate
        let outputCount = max(0, Int(Double(floatSamples.count) / ratio))
        var int16Samples = [Int16](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let srcIdx = Double(i) * ratio
            let idx0 = Int(srcIdx)
            let frac = Float(srcIdx - Double(idx0))
            let idx1 = min(idx0 + 1, floatSamples.count - 1)

            let sample: Float
            if idx0 < floatSamples.count {
                sample = floatSamples[idx0] * (1 - frac) + floatSamples[idx1] * frac
            } else {
                sample = 0
            }

            let clamped = max(-1.0, min(1.0, sample))
            int16Samples[i] = Int16(clamped * 32767)
        }

        floatSamples = []

        let pcmData = int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return WAVEncoder.encode(pcmData: pcmData, sampleRate: UInt32(targetSampleRate), channels: 1, bitsPerSample: 16)
    }

    // MARK: - System Default Device Management

    static func getDefaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &devID
        )
    }

    static func findBuiltInMicID() -> AudioDeviceID? {
        var propSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize)
        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &devices)

        for device in devices {
            // Check transport type
            var transportAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &transportAddr, 0, nil, &size, &transport)

            guard transport == kAudioDeviceTransportTypeBuiltIn else { continue }

            // Check has input channels
            var inputAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(device, &inputAddr, 0, nil, &inputSize)
            guard inputSize > 0 else { continue }

            return device
        }
        return nil
    }
}
