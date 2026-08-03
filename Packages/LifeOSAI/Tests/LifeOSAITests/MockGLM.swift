import Foundation
import LifeOSCore
@testable import LifeOSAI

enum MockGLM {
    static func service(stubbedResponse: String) -> GLMService {
        let store = InMemorySecretStore()
        let manager = GLMKeyManager(secretStore: store, metadataKey: "glm.mock.\(UUID().uuidString)")
        let glm = GLMService.makeForTesting(keyManager: manager)
        glm.debugCompleteHandler = { _ in stubbedResponse }
        glm.debugSendMessageHandler = { _, _, _ in stubbedResponse }
        return glm
    }
}
