// YappieTests/WAVEncoderTests.swift
import XCTest
@testable import Yappie

final class WAVEncoderTests: XCTestCase {

    func testEmptyPCMProducesValidHeader() {
        let wav = WAVEncoder.encode(pcmData: Data(), sampleRate: 16000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(wav.count, 44)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
    }

    func testHeaderFieldsAreCorrect() {
        let pcm = Data(repeating: 0, count: 1000)
        let wav = WAVEncoder.encode(pcmData: pcm, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        let chunkSize = wav.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        XCTAssertEqual(chunkSize, UInt32(36 + pcm.count))

        let audioFormat = wav.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt16.self) }
        XCTAssertEqual(audioFormat, 1)

        let channels = wav.withUnsafeBytes { $0.load(fromByteOffset: 22, as: UInt16.self) }
        XCTAssertEqual(channels, 1)

        let sampleRate = wav.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }
        XCTAssertEqual(sampleRate, 16000)

        let byteRate = wav.withUnsafeBytes { $0.load(fromByteOffset: 28, as: UInt32.self) }
        XCTAssertEqual(byteRate, 32000)

        let blockAlign = wav.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt16.self) }
        XCTAssertEqual(blockAlign, 2)

        let bps = wav.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt16.self) }
        XCTAssertEqual(bps, 16)

        let dataSize = wav.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }
        XCTAssertEqual(dataSize, UInt32(pcm.count))
    }

    func testPCMDataIsAppendedAfterHeader() {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let wav = WAVEncoder.encode(pcmData: pcm, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(wav.count, 44 + 4)
        XCTAssertEqual(wav[44], 0x01)
        XCTAssertEqual(wav[45], 0x02)
        XCTAssertEqual(wav[46], 0x03)
        XCTAssertEqual(wav[47], 0x04)
    }
}
