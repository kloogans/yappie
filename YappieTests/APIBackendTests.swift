// YappieTests/APIBackendTests.swift
import XCTest
@testable import Yappie

final class APIBackendTests: XCTestCase {

    func testMultipartBodyFormation() throws {
        let wavData = Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
        let boundary = "test-boundary-123"
        let body = APIBackend.buildMultipartBody(wavData: wavData, model: "whisper-1", boundary: boundary)

        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("--test-boundary-123"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\""))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"))
        XCTAssertTrue(bodyString.contains("name=\"model\""))
        XCTAssertTrue(bodyString.contains("whisper-1"))
        XCTAssertTrue(bodyString.contains("--test-boundary-123--"))
    }

    func testMultipartBodyWithoutModel() throws {
        let wavData = Data([0x52, 0x49, 0x46, 0x46])
        let boundary = "test-boundary-456"
        let body = APIBackend.buildMultipartBody(wavData: wavData, model: nil, boundary: boundary)

        let bodyString = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("name=\"file\""))
        XCTAssertFalse(bodyString.contains("name=\"model\""))
    }

    func testRequestConstruction() throws {
        let config = BackendConfig(
            name: "OpenAI",
            type: .api,
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            model: "whisper-1"
        )
        let apiKey = "sk-test-key"

        let request = try APIBackend.buildRequest(config: config, wavData: Data([0x00]), apiKey: apiKey)

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.contains("multipart/form-data"))
    }

    func testRequestWithoutAPIKey() throws {
        let config = BackendConfig(
            name: "Local",
            type: .api,
            enabled: true,
            baseURL: "http://localhost:8000/v1",
            model: nil
        )

        let request = try APIBackend.buildRequest(config: config, wavData: Data([0x00]), apiKey: nil)

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/v1/audio/transcriptions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testResponseParsing() throws {
        let json = #"{"text": "Hello world"}"#.data(using: .utf8)!
        let text = try APIBackend.parseResponse(data: json)
        XCTAssertEqual(text, "Hello world")
    }

    func testResponseParsingPlainText() throws {
        let plain = "Hello world".data(using: .utf8)!
        let text = try APIBackend.parseResponse(data: plain)
        XCTAssertEqual(text, "Hello world")
    }
}
