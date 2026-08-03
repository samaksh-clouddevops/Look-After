import Foundation
import LookAfterCore
@testable import LookAfterAI

enum MockGLM {
    static func service(stubbedResponse: String) -> GLMService {
        let store = InMemorySecretStore()
        let manager = GLMKeyManager(secretStore: store, metadataKey: "glm.mock.\(UUID().uuidString)")
        let glm = GLMService.makeForTesting(keyManager: manager)
        glm.debugCompleteHandler = { _, _ in stubbedResponse }
        glm.debugSendMessageHandler = { _, _, _, _ in stubbedResponse }
        return glm
    }
}
