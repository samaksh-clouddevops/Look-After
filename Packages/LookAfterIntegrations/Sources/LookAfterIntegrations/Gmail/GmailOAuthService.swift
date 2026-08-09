import Foundation
import Security
import LookAfterCore
import LookAfterAI

/// Stores Gmail OAuth tokens in Keychain.
public enum GmailTokenStore {
    private static let service = "com.lookafter.gmail"
    private static let account = "gmail_refresh_token"

    public static func saveRefreshToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func loadRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static var isConnected: Bool { loadRefreshToken() != nil }
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
        GmailTokenStore.saveRefreshToken("")
        isEnabled = false
    }
}
