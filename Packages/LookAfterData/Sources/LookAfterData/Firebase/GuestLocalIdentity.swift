import Foundation
import Security

/// Stable offline guest account id persisted in Keychain (never `String.hashValue`, never ephemeral UUID).
enum GuestLocalIdentity {
    static let service = "com.lookafter.guest-identity"
    static let account = "guest_user_uid"

    /// Returns the existing guest UID or creates and stores one.
    static func resolvedOrCreate() throws -> String {
        if let existing = try load(), !existing.isEmpty {
            return existing
        }
        let uid = "guest_\(UUID().uuidString.lowercased())"
        try save(uid)
        return uid
    }

    static func load() throws -> String? {
        var query: [String: Any] = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GuestLocalIdentityError.keychain(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw GuestLocalIdentityError.invalidData
        }
        return value
    }

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw GuestLocalIdentityError.keychain(updateStatus)
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GuestLocalIdentityError.keychain(addStatus)
        }
    }

    #if DEBUG
    static func deleteForTests() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GuestLocalIdentityError.keychain(status)
        }
    }
    #endif

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum GuestLocalIdentityError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Guest identity Keychain error (\(status))"
        case .invalidData: return "Guest identity Keychain data was invalid"
        }
    }
}
