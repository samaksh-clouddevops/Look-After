import Foundation
import Security
import LookAfterCore
import LookAfterAI

/// Stores Gmail OAuth tokens in Keychain.
public enum GmailTokenStore {
    private static let service = "com.lookafter.gmail"
    private static let account = "gmail_refresh_token"

    public static func saveRefreshToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw GmailTokenStoreError.keychain(updateStatus)
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GmailTokenStoreError.keychain(addStatus)
        }
    }

    public static func loadRefreshToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    public static func deleteRefreshToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GmailTokenStoreError.keychain(status)
        }
    }

    public static var isConnected: Bool { loadRefreshToken() != nil }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum GmailTokenStoreError: Error {
    case keychain(OSStatus)
}

/// Gmail OAuth scope management — extends Firebase Google sign-in.
public enum GmailOAuthService {
    public static let readOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "gmail_integration_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_integration_enabled") }
    }

    /// Stores token received from OAuth callback / Firebase extended scopes.
    public static func connect(refreshToken: String) {
        try? GmailTokenStore.saveRefreshToken(refreshToken)
        isEnabled = true
    }

    public static func disconnect() {
        try? GmailTokenStore.deleteRefreshToken()
        isEnabled = false
    }
}
