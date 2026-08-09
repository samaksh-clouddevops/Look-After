import Foundation
import LookAfterIntegrations

public enum GmailIntegrationSettings {
    public static var isEnabled: Bool {
        get { GmailOAuthService.isEnabled }
        set { GmailOAuthService.isEnabled = newValue }
    }

    public static var isConnected: Bool { GmailTokenStore.isConnected }
}
