import Foundation
import FirebaseCore

/// Central Firebase bootstrap — prefers bundled `GoogleService-Info.plist`, falls back to offline mock config.
public enum LookAfterFirebaseConfiguration {
    /// Valid-format placeholder key for offline/mock builds (39 chars, starts with `A`).
    public static let mockAPIKey = "AIzaSy000000000000000000000000000000000"

    public static func configureIfNeeded() {
        guard FirebaseApp.app() == nil else { return }

        if var options = bundledOptions() {
            if !isValidAPIKey(options.apiKey ?? "") {
                options.apiKey = mockAPIKey
            }
            FirebaseApp.configure(options: options)
        } else {
            FirebaseApp.configure(options: mockOptions())
        }
    }

    public static func isValidAPIKey(_ key: String) -> Bool {
        key.count == 39 && key.hasPrefix("A")
    }

    public static func mockOptions(projectID: String = "lifeos-dummy") -> FirebaseOptions {
        let options = FirebaseOptions(
            googleAppID: "1:1234567890:ios:1234567890abcdef",
            gcmSenderID: "1234567890"
        )
        options.apiKey = mockAPIKey
        options.projectID = projectID
        options.storageBucket = "\(projectID).appspot.com"
        return options
    }

    /// Firebase Auth OAuth callback scheme: `app-` + googleAppID with `:` → `-`.
    public static func oauthCallbackURLScheme(googleAppID: String? = nil) -> String? {
        let appID = googleAppID
            ?? FirebaseApp.app()?.options.googleAppID
            ?? bundledPlistString("GOOGLE_APP_ID")
        guard let appID, !appID.isEmpty else { return nil }
        return "app-" + appID.replacingOccurrences(of: ":", with: "-")
    }

    public static func bundledClientID() -> String? {
        bundledPlistString("CLIENT_ID")
    }

    public static func bundledReversedClientID() -> String? {
        bundledPlistString("REVERSED_CLIENT_ID")
    }

    private static func bundledOptions() -> FirebaseOptions? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return nil
        }
        return FirebaseOptions(contentsOfFile: path)
    }

    private static func bundledPlistString(_ key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let value = dict[key] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}

extension Bundle {
    /// URL schemes registered in Info.plist (`CFBundleURLTypes`).
    public var cfBundleURLSchemes: [String] {
        guard let types = object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }
        return types.flatMap { type in
            (type["CFBundleURLSchemes"] as? [String]) ?? []
        }
    }
}
