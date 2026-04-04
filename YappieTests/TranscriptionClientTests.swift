// YappieTests/TranscriptionClientTests.swift
import XCTest
import Network
@testable import Yappie

final class TranscriptionClientTests: XCTestCase {

    private func startMockServer(port: UInt16, response: String) -> NWListener {
        let listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            self.readAll(conn) { _ in
                let data = response.data(using: .utf8)!
                conn.send(content: data, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
        listener.start(queue: .global())
        return listener
    }

    private func readAll(_ conn: NWConnection, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            var acc = accumulated
            if let data { acc.append(data) }
            if isComplete {
                completion(acc)
            } else {
                self.readAll(conn, accumulated: acc, completion: completion)
            }
        }
    }

    func testSendAndReceive() async throws {
        let listener = startMockServer(port: 19876, response: "Hello world")
        defer { listener.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        let client = TranscriptionClient()
        let wavData = Data(repeating: 0, count: 100)
        let result = try await client.transcribe(wavData: wavData, host: "127.0.0.1", port: 19876)
        XCTAssertEqual(result, "Hello world")
    }

    func testServerError() async throws {
        let listener = startMockServer(port: 19877, response: "ERROR:GPU out of memory")
        defer { listener.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        let client = TranscriptionClient()
        let wavData = Data(repeating: 0, count: 100)

        do {
            _ = try await client.transcribe(wavData: wavData, host: "127.0.0.1", port: 19877)
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .serverError("GPU out of memory"))
        }
    }
}
