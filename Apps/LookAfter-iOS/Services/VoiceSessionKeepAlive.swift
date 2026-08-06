import Foundation
#if os(iOS)
import UIKit
#endif

/// Keeps the screen awake while the user is in an active voice conversation.
@MainActor
enum VoiceSessionKeepAlive {
    private static var tokens = Set<String>()

    static func begin(_ token: String) {
        tokens.insert(token)
        apply()
    }

    static func end(_ token: String) {
        tokens.remove(token)
        apply()
    }

    static func endAll() {
        tokens.removeAll()
        apply()
    }

    private static func apply() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = !tokens.isEmpty
        #endif
    }
}
