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
