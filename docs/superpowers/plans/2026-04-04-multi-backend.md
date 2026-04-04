# Multi-Backend Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add support for multiple configurable transcription backends (OpenAI-compatible API and raw TCP) with automatic fallback, replacing the current single hardcoded TCP connection.

**Architecture:** A `TranscriptionBackend` protocol defines the transcription interface. `APIBackend` and `TCPBackend` implement it. `BackendManager` holds an ordered list of backends and tries them in order until one succeeds. `BackendConfig` handles persistence (UserDefaults for config, Keychain for API keys). Preferences is rewritten with tabbed layout and a two-step wizard for adding backends.

**Tech Stack:** Swift 5.9+, macOS 14+, SwiftUI, Network.framework (TCP), URLSession (HTTP), Security.framework (Keychain)

---

## File Structure

```
Yappie/
├── BackendConfig.swift         # NEW — data model, JSON persistence, Keychain helper
├── TranscriptionBackend.swift  # NEW — protocol + BackendManager (fallback chain)
├── APIBackend.swift            # NEW — OpenAI-compatible HTTP transcription
├── TCPBackend.swift            # RENAMED from TranscriptionClient.swift, conforms to protocol
├── BackendWizard.swift         # NEW — two-step add/edit wizard views
├── Preferences.swift           # REWRITTEN — tabbed layout, backend cards
├── AppState.swift              # MODIFIED — uses BackendManager
├── YappieApp.swift             # MINOR — remove old server @AppStorage migration
```

Unchanged files: `AudioRecorder.swift`, `AudioFeedback.swift`, `WAVEncoder.swift`, `TextDelivery.swift`, `HotkeyManager.swift`

---

### Task 1: BackendConfig — Data Model and Persistence

**Files:**
- Create: `Yappie/BackendConfig.swift`
- Create: `YappieTests/BackendConfigTests.swift`

- [ ] **Step 1: Write failing tests for BackendConfig**

```swift
// YappieTests/BackendConfigTests.swift
import XCTest
@testable import Yappie

final class BackendConfigTests: XCTestCase {

    override func setUp() {
        // Clear test defaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "backends")
    }

    func testBackendConfigRoundTrip() {
        let backend = BackendConfig(
            name: "Test API",
            type: .api,
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            model: "whisper-1",
            host: nil,
            port: nil
        )

        let encoded = try! JSONEncoder().encode([backend])
        let decoded = try! JSONDecoder().decode([BackendConfig].self, from: encoded)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "Test API")
        XCTAssertEqual(decoded[0].type, .api)
        XCTAssertEqual(decoded[0].baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(decoded[0].model, "whisper-1")
        XCTAssertTrue(decoded[0].enabled)
    }

    func testBackendConfigTCP() {
        let backend = BackendConfig(
            name: "Home Server",
            type: .tcp,
            enabled: true,
            baseURL: nil,
            model: nil,
            host: "192.168.4.24",
            port: 9876
        )

        let encoded = try! JSONEncoder().encode([backend])
        let decoded = try! JSONDecoder().decode([BackendConfig].self, from: encoded)

        XCTAssertEqual(decoded[0].type, .tcp)
        XCTAssertEqual(decoded[0].host, "192.168.4.24")
        XCTAssertEqual(decoded[0].port, 9876)
    }

    func testBackendStoreLoadCycle() {
        let store = BackendStore()
        XCTAssertTrue(store.backends.isEmpty)

        var backend = BackendConfig(
            name: "OpenAI",
            type: .api,
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            model: "whisper-1",
            host: nil,
            port: nil
        )
        store.backends.append(backend)
        store.save()

        let store2 = BackendStore()
        XCTAssertEqual(store2.backends.count, 1)
        XCTAssertEqual(store2.backends[0].name, "OpenAI")
    }

    func testKeychainSaveAndRetrieve() {
        let testID = UUID()
        KeychainHelper.save(apiKey: "sk-test-key-123", forBackendID: testID)
        let retrieved = KeychainHelper.get(forBackendID: testID)
        XCTAssertEqual(retrieved, "sk-test-key-123")

        // Cleanup
        KeychainHelper.delete(forBackendID: testID)
        XCTAssertNil(KeychainHelper.get(forBackendID: testID))
    }

    func testKeychainUpdate() {
        let testID = UUID()
        KeychainHelper.save(apiKey: "old-key", forBackendID: testID)
        KeychainHelper.save(apiKey: "new-key", forBackendID: testID)
        XCTAssertEqual(KeychainHelper.get(forBackendID: testID), "new-key")

        KeychainHelper.delete(forBackendID: testID)
    }

    func testMigrationFromOldSettings() {
        let defaults = UserDefaults.standard
        defaults.set("192.168.4.24", forKey: "serverHost")
        defaults.set(9876, forKey: "serverPort")

        let store = BackendStore()
        store.migrateFromLegacySettings()

        XCTAssertEqual(store.backends.count, 1)
        XCTAssertEqual(store.backends[0].type, .tcp)
        XCTAssertEqual(store.backends[0].host, "192.168.4.24")
        XCTAssertEqual(store.backends[0].port, 9876)
        XCTAssertTrue(store.backends[0].enabled)

        // Old keys removed
        XCTAssertNil(defaults.string(forKey: "serverHost"))

        // Clean up
        defaults.removeObject(forKey: "backends")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test
```

Expected: FAIL — `BackendConfig` not found.

- [ ] **Step 3: Implement BackendConfig.swift**

```swift
// Yappie/BackendConfig.swift
import Foundation
import Security

// MARK: - Data Model

enum BackendType: String, Codable {
    case api
    case tcp
}

struct BackendConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: BackendType
    var enabled: Bool
    var baseURL: String?
    var model: String?
    var host: String?
    var port: Int?

    init(name: String, type: BackendType, enabled: Bool,
         baseURL: String? = nil, model: String? = nil,
         host: String? = nil, port: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.enabled = enabled
        self.baseURL = baseURL
        self.model = model
        self.host = host
        self.port = port
    }
}

// MARK: - Persistence

class BackendStore: ObservableObject {
    @Published var backends: [BackendConfig] = []

    private let key = "backends"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BackendConfig].self, from: data) else {
            backends = []
            return
        }
        backends = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(backends) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ backend: BackendConfig) {
        backends.append(backend)
        save()
    }

    func remove(at index: Int) {
        let backend = backends.remove(at: index)
        KeychainHelper.delete(forBackendID: backend.id)
        save()
    }

    func update(_ backend: BackendConfig) {
        guard let index = backends.firstIndex(where: { $0.id == backend.id }) else { return }
        backends[index] = backend
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        backends.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Migrate from the old single-server serverHost/serverPort settings.
    func migrateFromLegacySettings() {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "serverHost") else { return }
        let port = defaults.integer(forKey: "serverPort")

        let backend = BackendConfig(
            name: "Server",
            type: .tcp,
            enabled: true,
            host: host,
            port: port > 0 ? port : 9876
        )
        backends.append(backend)
        save()

        defaults.removeObject(forKey: "serverHost")
        defaults.removeObject(forKey: "serverPort")
    }
}

// MARK: - Keychain

enum KeychainHelper {
    private static let service = "com.kloogans.Yappie"

    static func save(apiKey: String, forBackendID id: UUID) {
        let account = id.uuidString
        let data = apiKey.data(using: .utf8)!

        // Delete existing first
        delete(forBackendID: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(forBackendID id: UUID) -> String? {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forBackendID id: UUID) {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Yappie/BackendConfig.swift YappieTests/BackendConfigTests.swift
git commit -m "feat: backend config data model with persistence and Keychain"
```

---

### Task 2: TranscriptionBackend Protocol + TCPBackend

**Files:**
- Create: `Yappie/TranscriptionBackend.swift`
- Rename: `Yappie/TranscriptionClient.swift` → `Yappie/TCPBackend.swift`
- Modify: `YappieTests/TranscriptionClientTests.swift`

- [ ] **Step 1: Create the TranscriptionBackend protocol**

```swift
// Yappie/TranscriptionBackend.swift
import Foundation

protocol TranscriptionBackend {
    func transcribe(wavData: Data) async throws -> String
}
```

- [ ] **Step 2: Rename TranscriptionClient.swift to TCPBackend.swift and conform to protocol**

Rename the file:
```bash
git mv Yappie/TranscriptionClient.swift Yappie/TCPBackend.swift
```

Edit `Yappie/TCPBackend.swift`:
- Rename `TranscriptionClient` class to `TCPBackend`
- Change the `transcribe` method signature to take a `BackendConfig` instead of separate host/port:

```swift
// Yappie/TCPBackend.swift
import Foundation
import Network

final class TCPBackend: TranscriptionBackend {
    private let host: String
    private let port: UInt16
    private static let queue = DispatchQueue(label: "yappie.tcp")

    init(config: BackendConfig) {
        self.host = config.host ?? "127.0.0.1"
        self.port = UInt16(config.port ?? 9876)
    }

    func transcribe(wavData: Data) async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            func resume(with result: Result<String, Error>) {
                lock.lock()
                guard !hasResumed else { lock.unlock(); return }
                hasResumed = true
                lock.unlock()
                switch result {
                case .success(let text): continuation.resume(returning: text)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                default:
                    break
                }
            }

            connection.start(queue: Self.queue)

            connection.send(content: wavData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    resume(with: .failure(TranscriptionError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                    return
                }

                self.readAll(connection) { data in
                    connection.cancel()

                    guard let data, !data.isEmpty else {
                        resume(with: .failure(TranscriptionError.emptyResponse))
                        return
                    }

                    guard let text = String(data: data, encoding: .utf8) else {
                        resume(with: .failure(TranscriptionError.emptyResponse))
                        return
                    }

                    if text.hasPrefix("ERROR:") {
                        let msg = String(text.dropFirst(6))
                        resume(with: .failure(TranscriptionError.serverError(msg)))
                    } else {
                        resume(with: .success(text))
                    }
                }
            })
        }
    }

    private func readAll(_ connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var acc = accumulated
            if let data { acc.append(data) }
            if isComplete || error != nil {
                completion(acc)
            } else {
                self.readAll(connection, accumulated: acc, completion: completion)
            }
        }
    }
}
```

- [ ] **Step 3: Update TranscriptionClientTests to use TCPBackend**

Edit `YappieTests/TranscriptionClientTests.swift` — rename references from `TranscriptionClient` to `TCPBackend`. The test creates a `BackendConfig` instead of passing host/port directly:

```swift
// YappieTests/TranscriptionClientTests.swift
import XCTest
import Network
@testable import Yappie

final class TCPBackendTests: XCTestCase {

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
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var acc = accumulated
            if let data { acc.append(data) }
            if isComplete || error != nil {
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

        let config = BackendConfig(name: "Test", type: .tcp, enabled: true, host: "127.0.0.1", port: 19876)
        let client = TCPBackend(config: config)
        let wavData = Data(repeating: 0, count: 100)
        let result = try await client.transcribe(wavData: wavData)
        XCTAssertEqual(result, "Hello world")
    }

    func testServerError() async throws {
        let listener = startMockServer(port: 19877, response: "ERROR:GPU out of memory")
        defer { listener.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        let config = BackendConfig(name: "Test", type: .tcp, enabled: true, host: "127.0.0.1", port: 19877)
        let client = TCPBackend(config: config)
        let wavData = Data(repeating: 0, count: 100)

        do {
            _ = try await client.transcribe(wavData: wavData)
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .serverError("GPU out of memory"))
        }
    }
}
```

- [ ] **Step 4: Build and run tests**

```bash
xcodegen generate && make test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: TranscriptionBackend protocol, rename TranscriptionClient to TCPBackend"
```

---

### Task 3: APIBackend — OpenAI-Compatible HTTP Transcription

**Files:**
- Create: `Yappie/APIBackend.swift`
- Create: `YappieTests/APIBackendTests.swift`

- [ ] **Step 1: Write failing tests for APIBackend**

```swift
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
        // OpenAI returns {"text": "transcribed text"}
        let json = #"{"text": "Hello world"}"#.data(using: .utf8)!
        let text = try APIBackend.parseResponse(data: json)
        XCTAssertEqual(text, "Hello world")
    }

    func testResponseParsingPlainText() throws {
        // Some servers return plain text
        let plain = "Hello world".data(using: .utf8)!
        let text = try APIBackend.parseResponse(data: plain)
        XCTAssertEqual(text, "Hello world")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test
```

Expected: FAIL — `APIBackend` not found.

- [ ] **Step 3: Implement APIBackend**

```swift
// Yappie/APIBackend.swift
import Foundation

final class APIBackend: TranscriptionBackend {
    private let config: BackendConfig
    private let apiKey: String?

    init(config: BackendConfig) {
        self.config = config
        self.apiKey = KeychainHelper.get(forBackendID: config.id)
    }

    func transcribe(wavData: Data) async throws -> String {
        let request = try Self.buildRequest(config: config, wavData: wavData, apiKey: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let text = try Self.parseResponse(data: data)
        guard !text.isEmpty else {
            throw TranscriptionError.emptyResponse
        }
        return text
    }

    // MARK: - Request Building (internal for testing)

    static func buildRequest(config: BackendConfig, wavData: Data, apiKey: String?) throws -> URLRequest {
        guard let baseURL = config.baseURL,
              let url = URL(string: baseURL)?.appendingPathComponent("audio/transcriptions") else {
            throw TranscriptionError.connectionFailed("Invalid base URL")
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = buildMultipartBody(wavData: wavData, model: config.model, boundary: boundary)
        return request
    }

    static func buildMultipartBody(wavData: Data, model: String?, boundary: String) -> Data {
        var body = Data()

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field (optional)
        if let model, !model.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Response Parsing

    static func parseResponse(data: Data) throws -> String {
        // Try JSON first: {"text": "..."}
        if let json = try? JSONDecoder().decode(WhisperResponse.self, from: data) {
            return json.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fall back to plain text
        guard let text = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WhisperResponse: Decodable {
    let text: String
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Yappie/APIBackend.swift YappieTests/APIBackendTests.swift
git commit -m "feat: APIBackend for OpenAI-compatible transcription endpoints"
```

---

### Task 4: BackendManager — Fallback Chain

**Files:**
- Modify: `Yappie/TranscriptionBackend.swift`
- Create: `YappieTests/BackendManagerTests.swift`

- [ ] **Step 1: Write failing tests for BackendManager**

```swift
// YappieTests/BackendManagerTests.swift
import XCTest
@testable import Yappie

// Mock backend for testing
final class MockBackend: TranscriptionBackend {
    var shouldFail = false
    var transcribeCallCount = 0
    var lastWavData: Data?
    var responseText = "mock response"

    func transcribe(wavData: Data) async throws -> String {
        transcribeCallCount += 1
        lastWavData = wavData
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
        let result = try await manager.transcribe(wavData: Data([0x00]))

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
        let result = try await manager.transcribe(wavData: Data([0x00]))

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
            _ = try await manager.transcribe(wavData: Data([0x00]))
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .allBackendsFailed)
        }
    }

    func testEmptyBackendsThrows() async {
        let manager = BackendManager(backends: [])

        do {
            _ = try await manager.transcribe(wavData: Data([0x00]))
            XCTFail("Should have thrown")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .allBackendsFailed)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test
```

Expected: FAIL — `BackendManager` not found.

- [ ] **Step 3: Implement BackendManager**

Update `Yappie/TranscriptionBackend.swift`:

```swift
// Yappie/TranscriptionBackend.swift
import Foundation

protocol TranscriptionBackend {
    func transcribe(wavData: Data) async throws -> String
}

struct TranscriptionResult {
    let text: String
    let backendIndex: Int
}

final class BackendManager {
    private let backends: [TranscriptionBackend]

    init(backends: [TranscriptionBackend]) {
        self.backends = backends
    }

    /// Build a BackendManager from a BackendStore's enabled backends.
    convenience init(store: BackendStore) {
        let enabledBackends: [TranscriptionBackend] = store.backends
            .filter { $0.enabled }
            .map { config in
                switch config.type {
                case .api: return APIBackend(config: config)
                case .tcp: return TCPBackend(config: config)
                }
            }
        self.init(backends: enabledBackends)
    }

    func transcribe(wavData: Data) async throws -> TranscriptionResult {
        guard !backends.isEmpty else {
            throw TranscriptionError.allBackendsFailed
        }

        for (index, backend) in backends.enumerated() {
            do {
                let text = try await backend.transcribe(wavData: wavData)
                return TranscriptionResult(text: text, backendIndex: index)
            } catch {
                NSLog("[Yappie] Backend %d failed: %@", index, "\(error)")
                continue
            }
        }

        throw TranscriptionError.allBackendsFailed
    }
}
```

Also add `allBackendsFailed` to `TranscriptionError` in `TCPBackend.swift`:

```swift
enum TranscriptionError: Error, Equatable {
    case connectionFailed(String)
    case serverError(String)
    case emptyResponse
    case allBackendsFailed
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: BackendManager with fallback chain"
```

---

### Task 5: Wire BackendManager into AppState

**Files:**
- Modify: `Yappie/AppState.swift`

- [ ] **Step 1: Update AppState to use BackendManager**

Replace the old `TranscriptionClient` + `serverHost`/`serverPort` with `BackendStore` and `BackendManager`. Remove the old `@AppStorage` for `serverHost` and `serverPort`.

```swift
// Yappie/AppState.swift
import SwiftUI

enum RecordingMode: String {
    case pushToTalk = "push-to-talk"
    case toggle = "toggle"
}

enum AppStatus {
    case idle
    case recording
    case transcribing
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var recordingDuration: TimeInterval = 0

    @AppStorage("recordingMode") var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") var deliveryMode: DeliveryMode = .clipboardAndPaste

    let backendStore = BackendStore()
    private let recorder = AudioRecorder()
    private let hotkeyManager = HotkeyManager()
    private var durationTimer: Timer?
    private var hasShownFallbackNotice = false

    var statusIcon: String {
        switch status {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        }
    }

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.setup()
        }
    }

    func setup() {
        // Migrate old settings if present
        if backendStore.backends.isEmpty {
            backendStore.migrateFromLegacySettings()
        }

        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        applyRecordingMode()

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyRecordingMode()
        }
    }

    func applyRecordingMode() {
        hotkeyManager.stopFnMonitor()
        hotkeyManager.unregisterToggleHotkey()

        if recordingMode == .pushToTalk {
            hotkeyManager.startFnMonitor()
        }
    }

    func startRecording() {
        guard status == .idle else { return }
        do {
            try recorder.startRecording()
            AudioFeedback.playStart()
            status = .recording
            recordingDuration = 0
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
        } catch {
            NSLog("[Yappie] Recording failed: %@", "\(error)")
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        durationTimer?.invalidate()
        durationTimer = nil

        AudioFeedback.playStop()
        let wavData = recorder.stopRecording()
        status = .transcribing

        Task { @MainActor in
            do {
                let manager = BackendManager(store: backendStore)
                let result = try await manager.transcribe(wavData: wavData)

                // Show fallback notification on first fallback per session
                if result.backendIndex > 0 && !hasShownFallbackNotice {
                    hasShownFallbackNotice = true
                    let name = backendStore.backends.filter { $0.enabled }[result.backendIndex].name
                    showNotification(title: "Yappie", body: "Using \(name)")
                }

                TextDelivery.deliver(result.text, mode: deliveryMode)
            } catch {
                NSLog("[Yappie] Transcription failed: %@", "\(error)")
                showNotification(title: "Yappie", body: "Transcription failed — no backends available")
            }
            status = .idle
        }
    }

    func toggleRecording() {
        if status == .idle {
            startRecording()
        } else if status == .recording {
            stopRecording()
        }
    }

    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodegen generate && make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: wire BackendManager into AppState with fallback notifications"
```

---

### Task 6: Preferences Rewrite — Tabbed Layout with Backend Cards

**Files:**
- Rewrite: `Yappie/Preferences.swift`

- [ ] **Step 1: Rewrite Preferences.swift with tabbed layout**

```swift
// Yappie/Preferences.swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("recordingMode") private var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("deliveryMode") private var deliveryMode: DeliveryMode = .clipboardAndPaste
    @ObservedObject var backendStore: BackendStore

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            backendsTab
                .tabItem { Label("Backends", systemImage: "server.rack") }
        }
        .frame(width: 500, height: 380)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Picker("Recording mode", selection: $recordingMode) {
                Text("Push-to-Talk (hold Fn)").tag(RecordingMode.pushToTalk)
                Text("Toggle (click menubar)").tag(RecordingMode.toggle)
            }
            .pickerStyle(.radioGroup)

            Picker("After transcription", selection: $deliveryMode) {
                Text("Copy & paste").tag(DeliveryMode.clipboardAndPaste)
                Text("Copy to clipboard only").tag(DeliveryMode.clipboardOnly)
            }
            .pickerStyle(.radioGroup)

            Toggle("Launch at login", isOn: launchAtLoginBinding)
        }
        .padding()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("[Yappie] Launch at login failed: %@", "\(error)")
                }
            }
        )
    }

    // MARK: - Backends Tab

    private var backendsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Backends")
                .font(.headline)
                .padding(.horizontal)

            Text("Backends are tried in order. If the first fails, the next one is used automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(backendStore.backends) { backend in
                    BackendCardView(backend: backend, store: backendStore)
                }
                .onMove { source, dest in
                    backendStore.move(from: source, to: dest)
                }
            }
            .listStyle(.plain)

            HStack {
                Spacer()
                Button("Add Backend…") {
                    showAddWizard = true
                }
                Spacer()
            }
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAddWizard) {
            BackendWizardView(store: backendStore)
        }
        .sheet(item: $editingBackend) { backend in
            BackendEditView(backend: backend, store: backendStore)
        }
    }

    @State private var showAddWizard = false
    @State private var editingBackend: BackendConfig?
}

// MARK: - Backend Card

struct BackendCardView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(backend.name)
                        .fontWeight(.medium)
                    priorityBadge
                }
                HStack(spacing: 6) {
                    Text(backend.type == .api ? "API" : "TCP")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(3)
                    Text(connectionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { backend.enabled },
                set: { newValue in
                    var updated = backend
                    updated.enabled = newValue
                    store.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit…") {
                // Handled by parent via editingBackend binding
            }
            Button("Delete", role: .destructive) {
                if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
                    store.remove(at: index)
                }
            }
        }
    }

    private var connectionDetail: String {
        switch backend.type {
        case .api:
            let url = backend.baseURL ?? ""
            let model = backend.model.map { " · \($0)" } ?? ""
            let key = KeychainHelper.get(forBackendID: backend.id) != nil ? " · ••••" : ""
            return "\(url)\(model)\(key)"
        case .tcp:
            return "\(backend.host ?? ""):\(backend.port ?? 0)"
        }
    }

    private var priorityBadge: some View {
        let enabledBackends = store.backends.filter { $0.enabled }
        let position = enabledBackends.firstIndex(where: { $0.id == backend.id })

        return Group {
            if let position, backend.enabled {
                Text(position == 0 ? "PRIMARY" : "FALLBACK")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(position == 0 ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(3)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && make build
```

Expected: BUILD SUCCEEDED (some warnings about unused `editingBackend` are OK for now — Task 7 will use it).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: rewrite Preferences with tabbed layout and backend cards"
```

---

### Task 7: Backend Wizard — Add/Edit Views

**Files:**
- Create: `Yappie/BackendWizard.swift`
- Modify: `Yappie/Preferences.swift` — wire up edit sheet
- Modify: `Yappie/YappieApp.swift` — pass backendStore to PreferencesView

- [ ] **Step 1: Create BackendWizard.swift**

```swift
// Yappie/BackendWizard.swift
import SwiftUI

// MARK: - Add Wizard (Two-Step)

struct BackendWizardView: View {
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: BackendType?

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Backend")
                .font(.headline)
                .padding()

            if let selectedType {
                BackendFormView(
                    type: selectedType,
                    store: store,
                    onSave: { dismiss() },
                    onBack: { self.selectedType = nil }
                )
            } else {
                typeSelectionView
            }
        }
        .frame(width: 420, height: 360)
    }

    private var typeSelectionView: some View {
        VStack(spacing: 12) {
            Button {
                selectedType = .api
            } label: {
                HStack(spacing: 12) {
                    Text("🌐").font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenAI-Compatible API")
                            .fontWeight(.medium)
                        Text("Works with OpenAI, Groq, Together AI, local servers like faster-whisper-server, and any service implementing the Whisper API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(.quaternary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                selectedType = .tcp
            } label: {
                HStack(spacing: 12) {
                    Text("🔌").font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom TCP Socket")
                            .fontWeight(.medium)
                        Text("Direct TCP connection — send WAV audio, receive text. For custom transcription servers on your network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(.quaternary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Backend Form (shared by Add and Edit)

struct BackendFormView: View {
    let type: BackendType
    @ObservedObject var store: BackendStore
    var existingBackend: BackendConfig?
    var onSave: () -> Void
    var onBack: (() -> Void)?

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var host: String = ""
    @State private var port: String = ""

    init(type: BackendType, store: BackendStore, existingBackend: BackendConfig? = nil, onSave: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.type = type
        self.store = store
        self.existingBackend = existingBackend
        self.onSave = onSave
        self.onBack = onBack

        if let existing = existingBackend {
            _name = State(initialValue: existing.name)
            _baseURL = State(initialValue: existing.baseURL ?? "")
            _model = State(initialValue: existing.model ?? "")
            _host = State(initialValue: existing.host ?? "")
            _port = State(initialValue: existing.port.map { String($0) } ?? "")
            _apiKey = State(initialValue: KeychainHelper.get(forBackendID: existing.id) ?? "")
        }
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text(type == .api ? "e.g. OpenAI" : "e.g. Home Server"))

            if type == .api {
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("Optional for local servers"))
                TextField("Model", text: $model, prompt: Text("e.g. whisper-1 (optional)"))
            } else {
                TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                TextField("Port", text: $port, prompt: Text("9876"))
            }
        }
        .padding()

        Spacer()

        HStack {
            if let onBack {
                Button("Back") { onBack() }
            }
            Spacer()
            Button("Cancel") { onSave() }
            Button(existingBackend == nil ? "Add" : "Save") {
                save()
            }
            .disabled(name.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func save() {
        if var existing = existingBackend {
            existing.name = name
            existing.baseURL = type == .api ? baseURL : nil
            existing.model = type == .api && !model.isEmpty ? model : nil
            existing.host = type == .tcp ? host : nil
            existing.port = type == .tcp ? Int(port) : nil

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: existing.id)
            } else if type == .api && apiKey.isEmpty {
                KeychainHelper.delete(forBackendID: existing.id)
            }

            store.update(existing)
        } else {
            let config = BackendConfig(
                name: name,
                type: type,
                enabled: true,
                baseURL: type == .api ? baseURL : nil,
                model: type == .api && !model.isEmpty ? model : nil,
                host: type == .tcp ? host : nil,
                port: type == .tcp ? Int(port) : nil
            )

            if type == .api && !apiKey.isEmpty {
                KeychainHelper.save(apiKey: apiKey, forBackendID: config.id)
            }

            store.add(config)
        }

        onSave()
    }
}

// MARK: - Edit View

struct BackendEditView: View {
    let backend: BackendConfig
    @ObservedObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Backend")
                .font(.headline)
                .padding()

            BackendFormView(
                type: backend.type,
                store: store,
                existingBackend: backend,
                onSave: { dismiss() }
            )
        }
        .frame(width: 420, height: 300)
    }
}
```

- [ ] **Step 2: Update Preferences.swift — wire edit sheet and context menu**

In `BackendCardView`, update the "Edit…" context menu button to set the parent's `editingBackend`:

Replace the `contextMenu` in `BackendCardView`:

```swift
        .contextMenu {
            Button("Delete", role: .destructive) {
                if let index = store.backends.firstIndex(where: { $0.id == backend.id }) {
                    store.remove(at: index)
                }
            }
        }
```

(Remove the non-functional "Edit…" button — editing will be via double-click or the context menu can be added later when the parent binding is available.)

- [ ] **Step 3: Update YappieApp.swift — pass backendStore to PreferencesView**

In `PreferencesWindowController.show()`, update to pass the backendStore:

```swift
final class PreferencesWindowController: ObservableObject {
    private var window: NSWindow?
    var backendStore: BackendStore?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView(backendStore: backendStore ?? BackendStore())
        let hostingView = NSHostingView(rootView: prefsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 380)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yappie Preferences"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

In `YappieApp.body`, wire the backendStore:

```swift
    var body: some Scene {
        MenuBarExtra("Yappie", systemImage: appState.statusIcon) {
            Button("Toggle Recording") {
                appState.toggleRecording()
            }

            Divider()

            Button("Preferences…") {
                prefsWindowController.backendStore = appState.backendStore
                prefsWindowController.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
```

- [ ] **Step 4: Build and verify**

```bash
xcodegen generate && make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: backend wizard and edit views, wire preferences to backend store"
```

---

### Task 8: Cleanup and README Update

**Files:**
- Modify: `README.md`
- Delete: old `default.profraw` or stale files if present

- [ ] **Step 1: Update README.md**

Update the README to reflect the new multi-backend setup. Replace the "Server setup" and "Configuration" sections:

```markdown
# Yappie

Fast dictation for macOS. Hold a key, speak, release, and the transcribed text gets pasted into whatever app you're using.

Yappie is a lightweight menubar app that sends audio to a speech-to-text server for transcription. It works with any OpenAI-compatible API (OpenAI, Groq, local Whisper servers) or custom TCP endpoints.

## How it works

1. **Hold Fn** to start recording
2. **Release Fn** to stop and transcribe
3. Text is copied to your clipboard and pasted automatically

Or use **toggle mode**: click the menubar icon to start, click again to stop.

## Requirements

- macOS 14+
- A transcription backend — either:
  - An OpenAI-compatible API endpoint (OpenAI, Groq, local faster-whisper-server, etc.)
  - A custom TCP transcription server

## Install

Clone and build with Xcode:

```bash
git clone https://github.com/kloogans/yappie.git
cd yappie
make build
```

Then open `Yappie.app` from the build output, or:

```bash
make run
```

## Configuration

Open **Preferences** from the menubar icon.

### Backends

Add one or more transcription backends. Yappie tries them in order — if the first fails, it automatically falls back to the next.

**OpenAI-Compatible API** — works with any service implementing the Whisper API format:
- [OpenAI](https://platform.openai.com) — `https://api.openai.com/v1` with your API key
- [Groq](https://groq.com) — `https://api.groq.com/openai/v1` with your API key
- [faster-whisper-server](https://github.com/fedirz/faster-whisper-server) — `http://your-server:8000/v1` (no API key needed)
- Any OpenAI-compatible endpoint

**Custom TCP** — direct socket connection for custom servers like [hypr-dictate](https://github.com/kloogans/hypr-dictate).

### General

- **Recording mode** — Push-to-talk (hold Fn) or toggle
- **After transcription** — Paste automatically or just copy to clipboard
- **Launch at login** — Start Yappie when you log in

## Permissions

Yappie needs two macOS permissions:

- **Microphone** — prompted automatically on first use
- **Accessibility** — needed for auto-paste (System Settings → Privacy & Security → Accessibility)

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "docs: update README for multi-backend support"
```

---

## Summary

| Task | What it builds | Tests |
|------|---------------|-------|
| 1 | BackendConfig data model, persistence, Keychain | XCTest — round trip, store, keychain, migration |
| 2 | TranscriptionBackend protocol, TCPBackend | XCTest — existing TCP tests updated |
| 3 | APIBackend (OpenAI-compatible HTTP) | XCTest — multipart body, request, response parsing |
| 4 | BackendManager (fallback chain) | XCTest — primary, fallback, all-fail |
| 5 | Wire BackendManager into AppState | Build verification |
| 6 | Preferences rewrite (tabbed, backend cards) | Build verification |
| 7 | Backend wizard (add/edit views) | Build verification |
| 8 | README update | N/A |
