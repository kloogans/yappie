// YappieTests/LocalBackendTests.swift
import XCTest
@testable import Yappie

final class LocalBackendTests: XCTestCase {

    func testThrowsWhenModelNotFound() async {
        do {
            _ = try await LocalBackend(modelFolder: "/nonexistent/path", language: nil)
            XCTFail("Should have thrown")
        } catch {
            // Expected: WhisperKit can't load from bad path
        }
    }

    func testExtractsLanguageFromConfig() {
        let config = BackendConfig(
            name: "Local",
            type: .local,
            enabled: true,
            model: "openai_whisper-tiny",
            language: "en"
        )
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.model, "openai_whisper-tiny")
    }

    func testAutoDetectLanguageIsNil() {
        let config = BackendConfig(
            name: "Local",
            type: .local,
            enabled: true,
            model: "openai_whisper-tiny",
            language: nil
        )
        XCTAssertNil(config.language)
    }
}
