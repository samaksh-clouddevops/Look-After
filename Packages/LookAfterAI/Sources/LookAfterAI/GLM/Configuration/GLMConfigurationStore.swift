import Foundation
import LookAfterCore

/// Persists GLM configuration.
public final class GLMConfigurationStore: @unchecked Sendable {
    public static let shared = GLMConfigurationStore()

    private let storageKey = "glmConfiguration"
    private let lock = NSLock()

    private init() {}

    public func load() -> GLMConfiguration {
        lock.lock()
        defer { lock.unlock() }
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let config = try? SharedFormatters.jsonDecoderSeconds.decode(GLMConfiguration.self, from: data)
        else {
            return .default
        }
        return config
    }

    public func save(_ configuration: GLMConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(configuration) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

#if DEBUG
extension GLMConfigurationStore {
    func clearForTesting() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
#endif
