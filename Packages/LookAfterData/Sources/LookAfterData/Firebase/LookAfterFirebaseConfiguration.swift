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

    private static func bundledOptions() -> FirebaseOptions? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return nil
        }
        return FirebaseOptions(contentsOfFile: path)
    }
}
