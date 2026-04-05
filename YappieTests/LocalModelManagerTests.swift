// YappieTests/LocalModelManagerTests.swift
import XCTest
@testable import Yappie

final class LocalModelManagerTests: XCTestCase {

    func testRecommendedModelFor8GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 8)
        XCTAssertEqual(model, "openai_whisper-small")
    }

    func testRecommendedModelFor16GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 16)
        XCTAssertEqual(model, "distil-whisper_distil-large-v3_turbo_600MB")
    }

    func testRecommendedModelFor24GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 24)
        XCTAssertEqual(model, "openai_whisper-large-v3_turbo_954MB")
    }

    func testRecommendedModelFor32GB() {
        let model = LocalModelManager.recommendedModel(ramGB: 32)
        XCTAssertEqual(model, "openai_whisper-large-v3_turbo_954MB")
    }

    func testModelDirectoryURL() {
        let url = LocalModelManager.modelDirectoryURL()
        XCTAssertTrue(url.path.contains("Application Support/Yappie/Models"))
    }

    func testCuratedModels() {
        let models = LocalModelManager.curatedModels
        XCTAssertEqual(models.count, 5)
        XCTAssertEqual(models[0].displayName, "Tiny")
        XCTAssertEqual(models[4].displayName, "Large v3")
    }

    func testIsAppleSiliconReturnsBool() {
        let result = LocalModelManager.isAppleSilicon()
        XCTAssertNotNil(result)
    }

    func testDeviceRAMReturnPositive() {
        let ram = LocalModelManager.deviceRAMInGB()
        XCTAssertGreaterThan(ram, 0)
    }
}
