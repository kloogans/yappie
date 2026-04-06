// Yappie/AudioRecorder.swift
import AVFoundation
import CoreAudio

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var floatSamples = [Float]()
    private let samplesLock = NSLock()
    private var hwSampleRate: Double = 44100
    private let targetSampleRate: Double = 16000

    private static var cachedBuiltInMicID: AudioDeviceID?

    func startRecording() throws {
        samplesLock.lock()
        floatSamples = []
        samplesLock.unlock()

        // Switch system default input to built-in mic (if available)
        // AVAudioEngine always uses the system default, so we must change it
        let originalDevice = Self.getDefaultInputDevice()
        let builtInID = Self.findBuiltInMicID()
        debugLog("[Yappie] Default input device: \(originalDevice), built-in mic: \(builtInID.map { String($0) } ?? "nil")")
        if let builtInID, builtInID != originalDevice {
            Self.setDefaultInputDevice(builtInID)
            debugLog("[Yappie] Switched default input to built-in mic (ID: \(builtInID))")
        } else if builtInID == nil {
            debugLog("[Yappie] WARNING: No built-in mic found!")
        } else {
            debugLog("[Yappie] Already using built-in mic")
        }

        // Create a fresh engine each time (device binding is per-engine)
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        hwSampleRate = hwFormat.sampleRate

        debugLog("[Yappie] Recording format: \(hwFormat.channelCount) ch, \(hwFormat.sampleRate) Hz")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            let invChannelCount = 1.0 / Float(channelCount)

            var mono = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][i]
                }
                mono[i] = sample * invChannelCount
            }

            self.samplesLock.lock()
            self.floatSamples.append(contentsOf: mono)
            self.samplesLock.unlock()
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stopRecording() -> Data {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil

        samplesLock.lock()
        let samples = floatSamples
        floatSamples = []
        samplesLock.unlock()

        // Downsample to 16kHz
        let ratio = hwSampleRate / targetSampleRate
        let outputCount = max(0, Int(Double(samples.count) / ratio))
        var int16Samples = [Int16](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let srcIdx = Double(i) * ratio
            let idx0 = Int(srcIdx)
            let frac = Float(srcIdx - Double(idx0))
            let idx1 = min(idx0 + 1, samples.count - 1)

            let sample: Float
            if idx0 < samples.count {
                sample = samples[idx0] * (1 - frac) + samples[idx1] * frac
            } else {
                sample = 0
            }

            let clamped = max(-1.0, min(1.0, sample))
            int16Samples[i] = Int16(clamped * 32767)
        }

        let pcmData = int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return WAVEncoder.encode(pcmData: pcmData, sampleRate: UInt32(targetSampleRate), channels: 1, bitsPerSample: 16)
    }

    // MARK: - System Default Device Management

    private static func getDefaultInputDevice() -> AudioDeviceID {
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

    private static func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
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

    private static func findBuiltInMicID() -> AudioDeviceID? {
        if let cached = cachedBuiltInMicID {
            return cached
        }

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

            cachedBuiltInMicID = device
            return device
        }
        return nil
    }
}
