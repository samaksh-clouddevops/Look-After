import Foundation
import LookAfterCore

/// The only AI networking layer — communicates directly with the official z.ai GLM API.
public final class GLMService: @unchecked Sendable {
    public static let shared = GLMService()

    private let configurationStore: GLMConfigurationStore
    private let keyManager: GLMKeyManager
    private let usageLogger: GLMUsageLogger
    private let session: URLSession

    /// When set, unused — AI calls use on-device GLM API keys directly (proxy optional / skipped).
    public var authProxyClient: AuthProxyClient?
    public var licenseStatusProvider: (any LicenseStatusProviding)?

    public init(
        configurationStore: GLMConfigurationStore = .shared,
        keyManager: GLMKeyManager = .shared,
        usageLogger: GLMUsageLogger = .shared
    ) {
        self.configurationStore = configurationStore
        self.keyManager = keyManager
        self.usageLogger = usageLogger

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configurationStore.load().requestTimeoutSeconds
        config.timeoutIntervalForResource = configurationStore.load().requestTimeoutSeconds * 2
        self.session = URLSession(configuration: config)
    }

    public var configuration: GLMConfiguration {
        configurationStore.load()
    }

    public func updateConfiguration(_ configuration: GLMConfiguration) {
        configurationStore.save(configuration)
    }

    public func usageSummary() -> GLMUsageSummary {
        usageLogger.summary()
    }

    public var keyManagerAccess: GLMKeyManager { keyManager }

    /// True when a local GLM API key (Keychain / env / bundled) can be used.
    public var hasConfiguredAPIKey: Bool {
        !keyManager.attemptableKeyPairs().isEmpty
    }

    /// Licensed Azure proxy path — retained for compatibility; chat uses direct keys.
    public var usesLicensedProxy: Bool {
        false
    }

#if DEBUG
    /// Test override — returns stubbed text without network.
    public var debugCompleteHandler: (@Sendable (String, AIModelTier) async throws -> String)?
    public var debugSendMessageHandler: (@Sendable (String, String?, [ChatMessage], AIModelTier) async throws -> String)?
#endif

    // MARK: - Public API

    /// Conversational chat with optional system prompt and history.
    public func sendMessage(
        _ message: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = [],
        tier: AIModelTier = .premium,
        maxTokens: Int = 4096
    ) async throws -> String {
#if DEBUG
        if let debugSendMessageHandler {
            return try await debugSendMessageHandler(message, systemPrompt, history, tier)
        }
#endif
        let config = configurationStore.load()
        var lastError: Error?

        for attemptTier in config.fallbackTiers(startingAt: tier) {
            do {
                let response = try await chatCompletion(
                    messages: buildMessages(message: message, systemPrompt: systemPrompt, history: history),
                    temperature: 0.7,
                    maxTokens: maxTokens,
                    tier: attemptTier
                )
                guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                return response.content
            } catch {
                lastError = error
            }
        }

        throw lastError ?? GLMServiceError.parseError("Empty model response")
    }

    /// Single-turn structured prompt (JSON extraction, task decomposition, etc.).
    public func complete(
        prompt: String,
        systemPrompt: String? = nil,
        tier: AIModelTier = .premium
    ) async throws -> String {
#if DEBUG
        if let debugCompleteHandler {
            return try await debugCompleteHandler(prompt, tier)
        }
#endif
        let system = systemPrompt ?? LookAfterPrompts.structuredOutputSystem
        let config = configurationStore.load()
        var lastError: Error?

        for attemptTier in config.fallbackTiers(startingAt: tier) {
            do {
                let response = try await chatCompletion(
                    messages: buildMessages(message: prompt, systemPrompt: system, history: []),
                    temperature: 0.3,
                    maxTokens: 8192,
                    tier: attemptTier
                )
                guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                return response.content
            } catch {
                lastError = error
            }
        }

        throw lastError ?? GLMServiceError.parseError("Empty model response")
    }

    /// Stream tokens for conversational UI.
    public func stream(
        message: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = [],
        tier: AIModelTier = .premium
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let config = self.configurationStore.load()
                    guard config.streamingEnabled else {
                        let text = try await self.sendMessage(
                            message,
                            systemPrompt: systemPrompt,
                            history: history,
                            tier: tier
                        )
                        continuation.yield(text)
                        continuation.finish()
                        return
                    }

                    let messages = self.buildMessages(message: message, systemPrompt: systemPrompt, history: history)
                    let primaryModel = config.model(for: tier)
                    let models = config.modelsToAttempt(primary: primaryModel)
                    var lastError: Error?

                    for model in models {
                        do {
                            try await self.executeWithRotation { apiKey, keyId in
                                let started = Date()
                                var promptTokens = 0
                                var completionTokens = 0
                                var resolvedModel = model

                                for try await chunk in self.streamCompletion(
                                    apiKey: apiKey,
                                    configuration: config,
                                    model: model,
                                    messages: messages,
                                    temperature: 0.7,
                                    maxTokens: 4096
                                ) {
                                    if let token = chunk.content, !token.isEmpty {
                                        continuation.yield(token)
                                    }
                                    if let m = chunk.model { resolvedModel = m }
                                    promptTokens = chunk.promptTokens ?? promptTokens
                                    completionTokens = chunk.completionTokens ?? completionTokens
                                }

                                let latency = Int(Date().timeIntervalSince(started) * 1000)
                                self.keyManager.recordSuccess(keyId: keyId)
                                self.usageLogger.log(GLMUsageRecord(
                                    model: resolvedModel,
                                    promptTokens: promptTokens,
                                    completionTokens: completionTokens,
                                    estimatedCostUSD: GLMUsageLogger.estimateCostUSD(
                                        model: resolvedModel,
                                        promptTokens: promptTokens,
                                        completionTokens: completionTokens
                                    ),
                                    latencyMs: latency,
                                    success: true
                                ))
                            }
                            continuation.finish()
                            return
                        } catch {
                            lastError = error
                            guard model != models.last, Self.shouldAttemptModelFallback(after: error) else {
                                throw error
                            }
                        }
                    }

                    throw lastError ?? GLMServiceError.parseError("Empty model response")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func testKey(id: String) async -> Result<String, Error> {
        guard let secret = keyManager.secret(for: id) else {
            return .failure(GLMServiceError.keyNotFound)
        }
        do {
            let client = makeClient(apiKey: secret)
            let result = try await client.chatCompletion(
                model: configuration.defaultModel,
                messages: [["role": "user", "content": "Reply with exactly: OK"]],
                temperature: 0,
                maxTokens: 256
            )
            let text = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw GLMServiceError.parseError("Model returned an empty response")
            }
            keyManager.recordSuccess(keyId: id)
            return .success(String(text.prefix(48)))
        } catch {
            if Self.isQuotaOrRateLimitError(error) {
                keyManager.markExhausted(keyId: id)
            } else {
                keyManager.recordFailure(keyId: id, error: error)
            }
            return .failure(error)
        }
    }

    // MARK: - HTTP

    private struct ChatResult {
        var content: String
        var model: String
        var promptTokens: Int
        var completionTokens: Int
        var latencyMs: Int
    }

    private struct StreamChunk {
        var content: String?
        var model: String?
        var promptTokens: Int?
        var completionTokens: Int?
    }

    private func chatCompletion(
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int,
        tier: AIModelTier
    ) async throws -> ChatResult {
        let config = configurationStore.load()
        let primaryModel = config.model(for: tier)
        let models = config.modelsToAttempt(primary: primaryModel)
        var lastError: Error?

        for model in models {
            do {
                return try await chatCompletion(
                    model: model,
                    messages: messages,
                    temperature: temperature,
                    maxTokens: maxTokens
                )
            } catch {
                lastError = error
                guard model != models.last, Self.shouldAttemptModelFallback(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? GLMServiceError.parseError("Empty model response")
    }

    private func chatCompletion(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> ChatResult {
        let config = configurationStore.load()
        let started = Date()

        return try await executeWithRotation { apiKey, keyId in
            let client = makeClient(apiKey: apiKey, configuration: config)
            do {
                let result = try await client.chatCompletion(
                    model: model,
                    messages: messages,
                    temperature: temperature,
                    maxTokens: maxTokens
                )
                keyManager.recordSuccess(keyId: keyId)
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                usageLogger.log(GLMUsageRecord(
                    model: result.model,
                    promptTokens: result.promptTokens,
                    completionTokens: result.completionTokens,
                    estimatedCostUSD: GLMUsageLogger.estimateCostUSD(
                        model: result.model,
                        promptTokens: result.promptTokens,
                        completionTokens: result.completionTokens
                    ),
                    latencyMs: latency,
                    success: true
                ))
                return ChatResult(
                    content: result.content,
                    model: result.model,
                    promptTokens: result.promptTokens,
                    completionTokens: result.completionTokens,
                    latencyMs: latency
                )
            } catch {
                if Self.isQuotaOrRateLimitError(error) {
                    keyManager.markExhausted(keyId: keyId)
                } else if keyId != "bundled", keyId != "env" {
                    keyManager.recordFailure(keyId: keyId, error: error)
                }
                throw error
            }
        }
    }

    private func executeWithRotation<T>(_ operation: (String, String) async throws -> T) async throws -> T {
        let keysToTry = keyManager.attemptableKeyPairs()
        guard !keysToTry.isEmpty else { throw GLMServiceError.noKeysConfigured }

        var lastError: Error?
        for pair in keysToTry {
            do {
                return try await operation(pair.secret, pair.keyId)
            } catch {
                lastError = error
                if Self.isQuotaOrRateLimitError(error) { continue }
                throw error
            }
        }
        throw lastError ?? GLMServiceError.allKeysExhausted
    }

    private func streamCompletion(
        apiKey: String,
        configuration: GLMConfiguration,
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let urlString = configuration.chatCompletionsURL
        let body: [String: Any] = Self.chatCompletionBody(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true
        )
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let session = self.session
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: urlString)!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
                    request.httpBody = bodyData

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GLMServiceError.networkError("Invalid response")
                    }
                    if http.statusCode == 401 { throw GLMServiceError.invalidAPIKey }
                    if http.statusCode == 429 { throw GLMServiceError.rateLimited }
                    guard http.statusCode == 200 else {
                        throw GLMServiceError.networkError("HTTP \(http.statusCode)")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard
                            let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        var chunk = StreamChunk()
                        if let model = json["model"] as? String { chunk.model = model }
                        if let usage = json["usage"] as? [String: Any] {
                            chunk.promptTokens = usage["prompt_tokens"] as? Int
                            chunk.completionTokens = usage["completion_tokens"] as? Int
                        }
                        if let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any] {
                            // Prefer assistant content only — do not stream reasoning_content into callers
                            // (GLM-5.3 always thinks; reasoning would corrupt JSON planners).
                            if let content = delta["content"] as? String, !content.isEmpty {
                                chunk.content = content
                            }
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeClient(apiKey: String, configuration: GLMConfiguration? = nil) -> GLMHTTPClient {
        GLMHTTPClient(apiKey: apiKey, configuration: configuration ?? configurationStore.load(), session: session)
    }

    private func buildMessages(message: String, systemPrompt: String?, history: [ChatMessage]) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        for msg in history {
            let role = msg.role == .assistant ? "assistant" : (msg.role == .system ? "system" : "user")
            messages.append(["role": role, "content": msg.content])
        }
        messages.append(["role": "user", "content": message])
        return messages
    }

    public static func isQuotaOrRateLimitError(_ error: Error) -> Bool {
        if case GLMServiceError.quotaExceeded = error { return true }
        if case GLMServiceError.rateLimited = error { return true }
        let message = error.localizedDescription.lowercased()
        return ["429", "quota", "rate limit", "too many requests"].contains { message.contains($0) }
    }

    /// Retry with glm-5.3-flash unless the API key itself is invalid.
    static func shouldAttemptModelFallback(after error: Error) -> Bool {
        if case GLMServiceError.invalidAPIKey = error { return false }
        return true
    }

    /// Builds chat body with model-aware thinking policy (GLM-5.3+ requires thinking enabled).
    static func chatCompletionBody(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": stream
        ]
        if GLMConfiguration.requiresMandatoryThinking(model) {
            body["thinking"] = ["type": "enabled"]
            body["reasoning_effort"] = GLMConfiguration.defaultReasoningEffort
        } else {
            body["thinking"] = ["type": "disabled"]
        }
        return body
    }
}

// MARK: - HTTP Client

private struct GLMHTTPClient {
    let apiKey: String
    let configuration: GLMConfiguration
    let session: URLSession

    struct CompletionResult {
        var content: String
        var model: String
        var promptTokens: Int
        var completionTokens: Int
    }

    func chatCompletion(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> CompletionResult {
        let url = URL(string: configuration.chatCompletionsURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let body: [String: Any] = GLMService.chatCompletionBody(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GLMServiceError.networkError("Invalid response")
        }
        if http.statusCode == 401 { throw GLMServiceError.invalidAPIKey }
        if http.statusCode == 429 { throw GLMServiceError.rateLimited }
        guard http.statusCode == 200 else {
            throw GLMServiceError.networkError(Self.apiErrorMessage(statusCode: http.statusCode, data: data))
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = Self.extractAssistantText(from: message)
        else {
            throw GLMServiceError.parseError("chat completion")
        }

        var promptTokens = 0
        var completionTokens = 0
        if let usage = json["usage"] as? [String: Any] {
            promptTokens = usage["prompt_tokens"] as? Int ?? 0
            completionTokens = usage["completion_tokens"] as? Int ?? 0
        }

        return CompletionResult(
            content: content,
            model: json["model"] as? String ?? model,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    static func extractAssistantText(from message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return content }
        }
        if let reasoning = message["reasoning_content"] as? String {
            let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return reasoning }
        }
        return message["content"] as? String
    }

    static func apiErrorMessage(statusCode: Int, data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "HTTP \(statusCode): \(message)"
        }
        let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
        return "HTTP \(statusCode): \(snippet)"
    }
}

#if DEBUG
extension GLMService {
    static func makeForTesting(keyManager: GLMKeyManager) -> GLMService {
        GLMService(keyManager: keyManager)
    }
}
#endif
