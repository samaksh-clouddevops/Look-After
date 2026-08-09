import Foundation
import Security
import LookAfterCore
import LookAfterAI

/// Stores Gmail OAuth tokens in Keychain.
public enum GmailTokenStore {
    private static let service = "com.lookafter.gmail"
    private static let account = "gmail_refresh_token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public static func saveRefreshToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteRefreshToken()
            return
        }

        let data = Data(trimmed.utf8)
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func loadRefreshToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Removes the Keychain item entirely (BUG-010).
    @discardableResult
    public static func deleteRefreshToken() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static var isConnected: Bool {
        guard let token = loadRefreshToken(), !token.isEmpty else { return false }
        return true
    }
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
        GmailTokenStore.saveRefreshToken(refreshToken)
        isEnabled = true
    }

    public static func disconnect() {
        GmailTokenStore.deleteRefreshToken()
        isEnabled = false
    }
}
