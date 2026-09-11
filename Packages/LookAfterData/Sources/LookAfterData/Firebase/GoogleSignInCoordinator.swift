import Foundation
import FirebaseAuth
import FirebaseCore
#if canImport(UIKit) && canImport(GoogleSignIn)
import UIKit
import GoogleSignIn
#endif

/// Native Google Sign-In → Firebase credential.
///
/// Avoids Firebase `OAuthProvider` web redirect, which fails on iOS with
/// “missing initial state” when ASWebAuthenticationSession partitions sessionStorage.
@MainActor
public enum GoogleSignInCoordinator {
    #if os(iOS) && canImport(GoogleSignIn)
    public static func signIn() async throws -> AuthCredential {
        LookAfterFirebaseConfiguration.configureIfNeeded()

        guard let clientID = FirebaseApp.app()?.options.clientID
            ?? LookAfterFirebaseConfiguration.bundledClientID()
        else {
            throw FirebaseManagerError.ssoFailed(
                "Google CLIENT_ID missing from GoogleService-Info.plist. Re-download after enabling Google Sign-In."
            )
        }

        let reversed = LookAfterFirebaseConfiguration.bundledReversedClientID()
        if let reversed, !Bundle.main.cfBundleURLSchemes.contains(reversed) {
            throw FirebaseManagerError.ssoFailed(
                "Missing URL scheme \(reversed) in Info.plist. Rebuild so the Firebase URL-scheme sync runs."
            )
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = topViewController() else {
            throw FirebaseManagerError.ssoFailed("No window to present Google Sign-In.")
        }

        let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: [gmailScope]
        )

        guard let idToken = result.user.idToken?.tokenString else {
            throw FirebaseManagerError.ssoFailed("Google identity token missing.")
        }
        let accessToken = result.user.accessToken.tokenString
        return GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
    }

    public static func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
    #else
    public static func handleOpenURL(_ url: URL) -> Bool { false }
    #endif
}
