// YappieTests/BackendConfigTests.swift
import XCTest
@testable import Yappie

final class BackendConfigTests: XCTestCase {

    override func setUp() {
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

        let backend = BackendConfig(
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

        XCTAssertNil(defaults.string(forKey: "serverHost"))

        defaults.removeObject(forKey: "backends")
    }
}
