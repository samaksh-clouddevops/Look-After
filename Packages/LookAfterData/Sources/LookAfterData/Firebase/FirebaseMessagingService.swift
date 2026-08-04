import Foundation
import FirebaseAuth
import FirebaseFirestore
import LookAfterCore

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Registers FCM device tokens in Firestore when cloud sync is available.
@MainActor
public final class FirebaseMessagingService: NSObject, ObservableObject {
    public static let shared = FirebaseMessagingService()

    private override init() {
        super.init()
    }

    public func configureIfAvailable() {
        guard FirebaseManager.shared.isCloudSyncAvailable else { return }
        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        Task { await refreshToken() }
        #endif
    }

    public func setAPNSToken(_ token: Data) {
        guard FirebaseManager.shared.isCloudSyncAvailable else { return }
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = token
        Task { await refreshToken() }
        #endif
    }

    public func refreshToken() async {
        guard FirebaseManager.shared.isCloudSyncAvailable else { return }
        #if canImport(FirebaseMessaging)
        do {
            let token = try await Messaging.messaging().token()
            try await storeToken(token)
        } catch {
            // FCM unavailable in mock/dev builds — local notifications still work.
        }
        #endif
    }

    private func storeToken(_ token: String) async throws {
        guard FirebaseManager.shared.isCloudSyncAvailable,
              let uid = Auth.auth().currentUser?.uid,
              let db = FirebaseManager.shared.db else { return }

        let device: [String: Any] = [
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("users")
            .document(uid)
            .collection("devices")
            .document(token)
            .setData(device, merge: true)
    }
}

#if canImport(FirebaseMessaging)
extension FirebaseMessagingService: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { try? await storeToken(fcmToken) }
    }
}
#endif
