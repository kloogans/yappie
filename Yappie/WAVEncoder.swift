// Yappie/WAVEncoder.swift
import Foundation

enum WAVEncoder {
    static func encode(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var wav = Data()
        wav.reserveCapacity(44 + pcmData.count)

        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLE(chunkSize)
        wav.append(contentsOf: "WAVE".utf8)

        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLE(UInt32(16))
        wav.appendLE(UInt16(1))
        wav.appendLE(channels)
        wav.appendLE(sampleRate)
        wav.appendLE(byteRate)
        wav.appendLE(blockAlign)
        wav.appendLE(bitsPerSample)

        wav.append(contentsOf: "data".utf8)
        wav.appendLE(dataSize)
        wav.append(pcmData)

        return wav
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
