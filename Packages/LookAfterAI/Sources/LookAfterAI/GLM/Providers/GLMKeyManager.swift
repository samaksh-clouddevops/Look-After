import Foundation
import LookAfterCore

/// Secure storage and health tracking for GLM API keys.
public final class GLMKeyManager: @unchecked Sendable {
    private let metadataKey: String
    private let legacyDefaultsKey = "geminiApiKey"
    private let legacyRecordsKey = "aiKeyRecords"
    private let secretStore: SecretStore
    private let lock = NSLock()
    private var records: [GLMKeyRecord] = []

    public init(secretStore: SecretStore = KeychainSecretStore(), metadataKey: String = "glmKeyRecords") {
        self.secretStore = secretStore
        self.metadataKey = metadataKey
        loadRecords()
        migrateLegacyKeysIfNeeded()
        seedBundledDefaultKeyIfNeeded()
    }

    public static let shared = GLMKeyManager()

    public func allRecords() -> [GLMKeyRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.sorted { $0.sortOrder < $1.sortOrder }
    }

    public func eligibleKeys() -> [GLMKeyRecord] {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        return records
            .filter(\.isEnabled)
            .filter { record in
                if let exhaustedUntil = record.exhaustedUntil, exhaustedUntil > now { return false }
                return record.consecutiveFailures < 5
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    public func secret(for keyId: String) -> String? {
        try? secretStore.load(account: keyId)
    }

    @discardableResult
    public func addKey(name: String, secret: String, isDefault: Bool = false) throws -> GLMKeyRecord {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GLMServiceError.noKeysConfigured }

        lock.lock()
        defer { lock.unlock() }

        let record = GLMKeyRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "API Key" : name,
            sortOrder: records.count,
            maskedSuffix: Self.maskedSuffix(for: trimmed),
            isDefault: isDefault || records.isEmpty
        )

        try secretStore.save(trimmed, account: record.id)

        if record.isDefault {
            for index in records.indices { records[index].isDefault = false }
        }

        records.append(record)
        persistLocked()
        return record
    }

    public func updateKey(
        id: String,
        name: String? = nil,
        isEnabled: Bool? = nil,
        isDefault: Bool? = nil,
        secret: String? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw GLMServiceError.keyNotFound
        }

        if let name { records[index].name = name }
        if let isEnabled { records[index].isEnabled = isEnabled }
        if let isDefault, isDefault {
            for i in records.indices { records[i].isDefault = (i == index) }
        }
        if let secret {
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try secretStore.save(trimmed, account: id)
            records[index].maskedSuffix = Self.maskedSuffix(for: trimmed)
            records[index].consecutiveFailures = 0
            records[index].exhaustedUntil = nil
        }

        persistLocked()
    }

    public func deleteKey(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll { $0.id == id }
        try? secretStore.delete(account: id)
        reindexLocked()
        persistLocked()
    }

    public func reorderKeys(ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        for (order, id) in ids.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == id }) else { continue }
            records[index].sortOrder = order
        }
        persistLocked()
    }

    public func recordSuccess(keyId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == keyId }) else { return }
        let now = Date()
        records[index].lastSuccessfulRequest = now
        records[index].lastUsedAt = now
        records[index].consecutiveFailures = 0
        records[index].exhaustedUntil = nil
        records[index].lastFailure = nil
        records[index].lastFailureReason = nil
        persistLocked()
    }

    public func recordFailure(keyId: String, error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == keyId }) else { return }
        records[index].lastFailure = Date()
        records[index].lastFailureReason = Self.sanitizedError(error)
        records[index].consecutiveFailures += 1
        persistLocked()
    }

    public func markExhausted(keyId: String, cooldown: TimeInterval = 3600) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == keyId }) else { return }
        records[index].lastFailure = Date()
        records[index].lastFailureReason = "Quota or rate limit exceeded"
        records[index].consecutiveFailures += 1
        records[index].exhaustedUntil = Date().addingTimeInterval(cooldown)
        persistLocked()
    }

    public func resetHealth(for keyId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == keyId }) else { return }
        records[index].consecutiveFailures = 0
        records[index].exhaustedUntil = nil
        records[index].lastFailure = nil
        records[index].lastFailureReason = nil
        persistLocked()
    }

    public func activeKeyDisplay() -> GLMKeyRecord? {
        eligibleKeys().first ?? allRecords().first(where: \.isEnabled)
    }

    /// Removes every stored key and wipes legacy Gemini metadata from UserDefaults.
    public func clearAllKeys() {
        lock.lock()
        defer { lock.unlock() }
        for record in records {
            try? secretStore.delete(account: record.id)
        }
        records = []
        persistLocked()
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyRecordsKey)
    }

    public func resolveAPIKey() -> String? {
        if let record = eligibleKeys().first, let secret = secret(for: record.id) {
            return secret
        }
        let env = ProcessInfo.processInfo.environment
        for key in [GLMConfiguration.apiKeyEnvVar, GLMConfiguration.legacyEnvVar] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Keys to try for API calls — eligible first, then degraded stored keys, then bundled default.
    public func attemptableKeyPairs() -> [(secret: String, keyId: String)] {
        var seen = Set<String>()
        var pairs: [(String, String)] = []

        func append(from records: [GLMKeyRecord]) {
            for record in records {
                guard record.isEnabled, let secret = secret(for: record.id) else { continue }
                let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                pairs.append((trimmed, record.id))
            }
        }

        append(from: eligibleKeys())
        if pairs.isEmpty {
            append(from: allRecords())
        }

        let bundled = GLMConfiguration.bundledDefaultAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bundled.isEmpty, !seen.contains(bundled) {
            pairs.append((bundled, "bundled"))
        }

        if pairs.isEmpty {
            let env = ProcessInfo.processInfo.environment
            for key in [GLMConfiguration.apiKeyEnvVar, GLMConfiguration.legacyEnvVar] {
                if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    pairs.append((value, "env"))
                    break
                }
            }
        }

        return pairs
    }

    // MARK: - Private

    private func loadRecords() {
        guard
            let data = UserDefaults.standard.data(forKey: metadataKey),
            let decoded = try? JSONDecoder().decode([GLMKeyRecord].self, from: data)
        else {
            records = []
            return
        }
        records = decoded
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private func reindexLocked() {
        for index in records.indices { records[index].sortOrder = index }
        if !records.contains(where: \.isDefault), !records.isEmpty {
            records[0].isDefault = true
        }
    }

    private func migrateLegacyKeysIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard records.isEmpty else { return }

        if let legacyData = UserDefaults.standard.data(forKey: legacyRecordsKey),
           let legacyRecords = try? JSONDecoder().decode([LegacyKeyRecord].self, from: legacyData) {
            for legacy in legacyRecords {
                guard let secret = try? secretStore.load(account: legacy.id) else { continue }
                let record = GLMKeyRecord(
                    id: legacy.id,
                    name: legacy.name.hasPrefix("Legacy") ? legacy.name : "Legacy (Gemini) — \(legacy.name)",
                    isEnabled: legacy.isEnabled,
                    sortOrder: legacy.sortOrder,
                    maskedSuffix: legacy.maskedSuffix,
                    isDefault: legacy.isDefault
                )
                records.append(record)
                try? secretStore.save(secret, account: record.id)
            }
            if !records.isEmpty {
                persistLocked()
                UserDefaults.standard.removeObject(forKey: legacyRecordsKey)
                return
            }
        }

        if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            let record = GLMKeyRecord(
                name: "Legacy (Gemini) — Personal",
                sortOrder: 0,
                maskedSuffix: Self.maskedSuffix(for: legacy),
                isDefault: true
            )
            do {
                try secretStore.save(legacy, account: record.id)
                records = [record]
                persistLocked()
                UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            } catch {}
        }
    }

    private func seedBundledDefaultKeyIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard records.isEmpty else { return }

        let bundled = GLMConfiguration.bundledDefaultAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundled.isEmpty else { return }

        let record = GLMKeyRecord(
            name: "\(UserFacingCopy.productName) Default",
            sortOrder: 0,
            maskedSuffix: Self.maskedSuffix(for: bundled),
            isDefault: true
        )
        do {
            try secretStore.save(bundled, account: record.id)
            records = [record]
            persistLocked()
        } catch {}
    }

    /// Syncs GLM key from `~/ADHD/credentials` (creates or updates "Developer credentials").
    @discardableResult
    public func syncDeveloperCredentials(
        credentialsURL: URL? = nil
    ) -> Bool {
        let env = ProcessInfo.processInfo.environment
        for key in [GLMConfiguration.apiKeyEnvVar, GLMConfiguration.legacyEnvVar] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return upsertNamedKey(name: "Environment (\(key))", secret: value, makeDefault: true)
            }
        }

        let url = credentialsURL ?? Self.defaultDeveloperCredentialsURL()
        guard
            let url,
            let text = try? String(contentsOf: url, encoding: .utf8),
            let secret = Self.credentialValue(from: text, keys: ["glm_api_key", "GLM_API_KEY"])
        else {
            return false
        }

        return upsertNamedKey(name: "Developer credentials", secret: secret, makeDefault: true)
    }

    /// Seeds a Keychain key from `~/ADHD/credentials` when no keys exist.
    @discardableResult
    public func seedFromDeveloperCredentialsIfNeeded(
        credentialsURL: URL? = nil
    ) -> Bool {
        lock.lock()
        let hasRecords = !records.isEmpty
        lock.unlock()
        if hasRecords {
            return syncDeveloperCredentials(credentialsURL: credentialsURL)
        }
        return syncDeveloperCredentials(credentialsURL: credentialsURL)
    }

    @discardableResult
    private func upsertNamedKey(name: String, secret: String, makeDefault: Bool) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        lock.lock()
        let existing = records.first(where: { $0.name == name })
        lock.unlock()

        do {
            if let existing {
                try updateKey(id: existing.id, isDefault: makeDefault ? true : nil, secret: trimmed)
            } else {
                _ = try addKey(name: name, secret: trimmed, isDefault: makeDefault)
            }
            return true
        } catch {
            return false
        }
    }

    private static func defaultDeveloperCredentialsURL() -> URL? {
        var candidates: [URL] = []
        #if targetEnvironment(simulator)
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"], !hostHome.isEmpty {
            candidates.append(URL(fileURLWithPath: hostHome).appendingPathComponent("ADHD/credentials"))
        }
        #endif
        #if os(macOS)
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ADHD/credentials"))
        #endif
        candidates.append(URL(fileURLWithPath: "/Users/samaksh/ADHD/credentials"))

        for candidate in candidates {
            if FileManager.default.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func credentialValue(from text: String, keys: [String]) -> String? {
        let lowered = Set(keys.map { $0.lowercased() })
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard lowered.contains(key) else { continue }
            let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Syncs OpenAI key from env/`~/ADHD/credentials` into Keychain for cloud TTS.
    @discardableResult
    public func syncOpenAIDeveloperCredentials(credentialsURL: URL? = nil) -> Bool {
        if let key = Self.resolveOpenAIAPIKey(credentialsURL: credentialsURL, preferKeychain: false) {
            return storeOpenAIAPIKey(key)
        }
        let existing = loadOpenAIAPIKey()
        let configured = !(existing?.isEmpty ?? true)
        SpeechVoiceSettings.isOpenAIKeyConfigured = configured
        return configured
    }

    @discardableResult
    public func storeOpenAIAPIKey(_ secret: String) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SpeechVoiceSettings.isOpenAIKeyConfigured = false
            return false
        }
        do {
            try secretStore.save(trimmed, account: Self.openAIKeychainAccount)
            SpeechVoiceSettings.isOpenAIKeyConfigured = true
            return true
        } catch {
            SpeechVoiceSettings.isOpenAIKeyConfigured = false
            return false
        }
    }

    public func loadOpenAIAPIKey() -> String? {
        guard let raw = try? secretStore.load(account: Self.openAIKeychainAccount) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let openAIKeychainAccount = "openai_api_key"

    /// OpenAI key from Keychain → env → credentials file (for direct cloud TTS).
    public static func resolveOpenAIAPIKey(
        credentialsURL: URL? = nil,
        preferKeychain: Bool = true
    ) -> String? {
        if preferKeychain, let stored = shared.loadOpenAIAPIKey() {
            return stored
        }

        let env = ProcessInfo.processInfo.environment
        if let value = env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        let url = credentialsURL ?? defaultDeveloperCredentialsURL()
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return credentialValue(from: text, keys: ["openai_api_key", "OPENAI_API_KEY"])
    }

    private static func maskedSuffix(for secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "****" }
        return String(trimmed.suffix(4))
    }

    private static func sanitizedError(_ error: Error) -> String {
        error.localizedDescription.replacingOccurrences(
            of: #"[A-Za-z0-9._-]{20,}"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
    }

    private struct LegacyKeyRecord: Codable {
        var id: String
        var name: String
        var isEnabled: Bool
        var sortOrder: Int
        var maskedSuffix: String
        var isDefault: Bool
    }
}

#if DEBUG
extension GLMKeyManager {
    func replaceRecordsForTesting(_ newRecords: [GLMKeyRecord]) {
        lock.lock()
        records = newRecords
        persistLocked()
        lock.unlock()
    }

    func clearAllForTesting() {
        lock.lock()
        for record in records { try? secretStore.delete(account: record.id) }
        records = []
        persistLocked()
        lock.unlock()
    }
}
#endif
