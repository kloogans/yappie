// Yappie/AudioRecorder.swift
import AVFoundation
import CoreAudio
import WhisperKit

final class AudioRecorder {
    private let engine = AVAudioEngine()
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

        // Reset engine to pick up any device changes
        engine.reset()
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
    }

    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        samplesLock.lock()
        let samples = floatSamples
        floatSamples.removeAll(keepingCapacity: true)
        samplesLock.unlock()

        guard !samples.isEmpty else { return [] }

        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hwSampleRate, channels: 1, interleaved: false)!
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            debugLog("[Yappie] Failed to create input buffer for resampling")
            return []
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(inputBuffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)

        guard let resampled = AudioProcessor.resampleAudio(fromBuffer: inputBuffer, toSampleRate: targetSampleRate, channelCount: 1) else {
            debugLog("[Yappie] Resampling failed")
            return []
        }
        return AudioProcessor.convertBufferToArray(buffer: resampled)
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
