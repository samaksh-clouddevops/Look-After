import Foundation
import Security

public protocol SecretStore {
    func save(_ value: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

enum KeychainStore {
    static let service = "com.samaksh.flowos.ai-keys"

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
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStore.KeychainError.saveFailed(status)
        }
    }

    public func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
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

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStore.KeychainError.deleteFailed(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
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
