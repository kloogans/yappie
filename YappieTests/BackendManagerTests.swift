// YappieTests/BackendManagerTests.swift
import XCTest
@testable import Yappie

final class MockBackend: TranscriptionBackend {
    var shouldFail = false
    var transcribeCallCount = 0
    var responseText = "mock response"

    func transcribe(audioSamples: [Float]) async throws -> String {
        transcribeCallCount += 1
        if shouldFail {
            throw TranscriptionError.connectionFailed("Mock connection failed")
        }
        return responseText
    }
}

final class BackendManagerTests: XCTestCase {

    func testTriesFirstBackend() async throws {
        let primary = MockBackend()
        primary.responseText = "primary result"
        let fallback = MockBackend()
        fallback.responseText = "fallback result"

        let manager = BackendManager(backends: [primary, fallback])
        let result = try await manager.transcribe(audioSamples: [0.0])

        XCTAssertEqual(result.text, "primary result")
        XCTAssertEqual(result.backendIndex, 0)
        XCTAssertEqual(primary.transcribeCallCount, 1)
        XCTAssertEqual(fallback.transcribeCallCount, 0)
    }

    func testFallsBackOnFailure() async throws {
        let primary = MockBackend()
        primary.shouldFail = true
        let fallback = MockBackend()
        fallback.responseText = "fallback result"

        let manager = BackendManager(backends: [primary, fallback])
        let result = try await manager.transcribe(audioSamples: [0.0])

        XCTAssertEqual(result.text, "fallback result")
        XCTAssertEqual(result.backendIndex, 1)
        XCTAssertEqual(primary.transcribeCallCount, 1)
        XCTAssertEqual(fallback.transcribeCallCount, 1)
    }

    func testAllFailThrows() async {
        let primary = MockBackend()
        primary.shouldFail = true
        let fallback = MockBackend()
        fallback.shouldFail = true

        let manager = BackendManager(backends: [primary, fallback])

        do {
            _ = try await manager.transcribe(audioSamples: [0.0])
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .allBackendsFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testEmptyBackendsThrows() async {
        let manager = BackendManager(backends: [])

        do {
            _ = try await manager.transcribe(audioSamples: [0.0])
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .allBackendsFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLocalBackendInFallbackChain() async throws {
        let local = MockBackend()
        local.shouldFail = true
        local.responseText = "local result"
        let cloud = MockBackend()
        cloud.responseText = "cloud result"

        let manager = BackendManager(backends: [local, cloud])
        let result = try await manager.transcribe(audioSamples: [0.0])

        XCTAssertEqual(result.text, "cloud result")
        XCTAssertEqual(result.backendIndex, 1)
        XCTAssertEqual(local.transcribeCallCount, 1)
        XCTAssertEqual(cloud.transcribeCallCount, 1)
    }
}
