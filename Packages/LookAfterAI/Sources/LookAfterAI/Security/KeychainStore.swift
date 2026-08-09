import Foundation
import Security

public protocol SecretStore {
    func save(_ value: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

enum KeychainStore {
    /// Canonical service id after brand migration (BUG-027).
    static let service = "com.lookafter.ai-keys"
    /// Pre-migration service id — still read so existing installs keep API keys.
    static let legacyService = "com.samaksh.flowos.ai-keys"

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case invalidData
    }
}

public struct KeychainSecretStore: SecretStore {
    public init() {}

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        // Prefer canonical service; clear both so we don't leave duplicate secrets.
        SecItemDelete(baseQuery(account: account, service: KeychainStore.service) as CFDictionary)
        SecItemDelete(baseQuery(account: account, service: KeychainStore.legacyService) as CFDictionary)

        var addQuery = baseQuery(account: account, service: KeychainStore.service)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStore.KeychainError.saveFailed(status)
        }
    }

    public func load(account: String) throws -> String? {
        if let value = try load(account: account, service: KeychainStore.service) {
            return value
        }
        // Migrate-on-read from legacy brand service id.
        if let legacy = try load(account: account, service: KeychainStore.legacyService) {
            try? save(legacy, account: account)
            return legacy
        }
        return nil
    }

    public func delete(account: String) throws {
        let primary = SecItemDelete(baseQuery(account: account, service: KeychainStore.service) as CFDictionary)
        let legacy = SecItemDelete(baseQuery(account: account, service: KeychainStore.legacyService) as CFDictionary)
        let ok: Set<OSStatus> = [errSecSuccess, errSecItemNotFound]
        guard ok.contains(primary) || ok.contains(legacy) else {
            throw KeychainStore.KeychainError.deleteFailed(primary)
        }
    }

    private func load(account: String, service: String) throws -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStore.KeychainError.readFailed(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStore.KeychainError.invalidData
        }
        return value
    }

    private func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

#if DEBUG
final class InMemorySecretStore: SecretStore {
    private var secrets: [String: String] = [:]

    func save(_ value: String, account: String) throws {
        secrets[account] = value
    }

    func load(account: String) throws -> String? {
        secrets[account]
    }

    func delete(account: String) throws {
        secrets.removeValue(forKey: account)
    }

    func removeAll() {
        secrets.removeAll()
    }
}
#endif
