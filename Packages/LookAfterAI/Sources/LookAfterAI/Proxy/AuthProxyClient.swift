import Foundation
import LookAfterCore

public enum AuthProxyError: Error, LocalizedError, Sendable {
    case notConfigured
    case missingToken
    case licenseRequired
    case httpStatus(Int, String)
    case decodeFailed
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Auth proxy is not configured"
        case .missingToken: return "Sign in required to activate. Sign out and sign in again, then retry."
        case .licenseRequired: return "A product key is required for AI"
        case .httpStatus(let code, let message): return "Proxy HTTP \(code): \(message)"
        case .decodeFailed: return "Failed to decode proxy response"
        case .emptyResponse: return "Proxy returned an empty response"
        }
    }
}

/// HTTP client for the Azure auth-proxy (license + GLM). Never receives raw API keys.
public final class AuthProxyClient: @unchecked Sendable {
    public let configuration: AuthProxyConfiguration
    private let tokenProvider: any AuthProxyTokenProviding
    private let session: URLSession

    public init(
        configuration: AuthProxyConfiguration,
        tokenProvider: any AuthProxyTokenProviding,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public struct LicenseStatus: Decodable, Sendable {
        public var active: Bool
        public var redeemedAt: String?
    }

    public struct RedeemResult: Decodable, Sendable {
        public var active: Bool
        public var alreadyOwned: Bool?
    }

    public struct AIResult: Decodable, Sendable {
        public var content: String
        public var model: String?
    }

    public func redeem(productKey: String) async throws -> RedeemResult {
        struct Body: Encodable { let productKey: String }
        return try await postJSON(
            path: "/v1/license/redeem",
            body: Body(productKey: productKey.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    public func licenseStatus() async throws -> LicenseStatus {
        try await getJSON(path: "/v1/license/status")
    }

    public func chat(
        message: String,
        systemPrompt: String?,
        history: [[String: String]],
        model: String,
        maxTokens: Int
    ) async throws -> AIResult {
        struct Body: Encodable {
            let message: String
            let systemPrompt: String?
            let history: [[String: String]]
            let model: String
            let max_tokens: Int
        }
        return try await postJSON(
            path: "/v1/ai/chat",
            body: Body(
                message: message,
                systemPrompt: systemPrompt,
                history: history,
                model: model,
                max_tokens: maxTokens
            )
        )
    }

    public func complete(
        prompt: String,
        systemPrompt: String?,
        model: String
    ) async throws -> AIResult {
        struct Body: Encodable {
            let prompt: String
            let systemPrompt: String?
            let model: String
        }
        return try await postJSON(
            path: "/v1/ai/complete",
            body: Body(prompt: prompt, systemPrompt: systemPrompt, model: model)
        )
    }

    /// Proxied OpenAI TTS — returns MP3 audio bytes (never exposes OpenAI key to the client).
    public func speech(
        input: String,
        voice: String = "nova",
        speed: Double? = nil,
        model: String = "tts-1-hd"
    ) async throws -> Data {
        struct Body: Encodable {
            let input: String
            let voice: String
            let speed: Double?
            let model: String
        }
        var request = try await authorizedRequest(path: "/v1/ai/speech", method: "POST")
        request.httpBody = try SharedFormatters.jsonEncoderSeconds.encode(
            Body(input: input, voice: voice, speed: speed, model: model)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthProxyError.httpStatus(-1, "Invalid response")
        }
        if http.statusCode == 403 {
            throw AuthProxyError.licenseRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AuthProxyError.httpStatus(http.statusCode, String(message.prefix(200)))
        }
        guard !data.isEmpty else { throw AuthProxyError.emptyResponse }
        return data
    }

    // MARK: - HTTP

    private func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        guard let token = try await tokenProvider.idToken(forceRefresh: false), !token.isEmpty else {
            throw AuthProxyError.missingToken
        }
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let resolved = URL(string: base + normalizedPath) else {
            throw AuthProxyError.notConfigured
        }
        var request = URLRequest(url: resolved)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        return request
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let request = try await authorizedRequest(path: path, method: "GET")
        return try await decode(request)
    }

    private func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        var request = try await authorizedRequest(path: path, method: "POST")
        request.httpBody = try SharedFormatters.jsonEncoderSeconds.encode(body)
        return try await decode(request)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthProxyError.httpStatus(-1, "Invalid response")
        }
        if http.statusCode == 403 {
            throw AuthProxyError.licenseRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AuthProxyError.httpStatus(http.statusCode, String(message.prefix(200)))
        }
        do {
            return try SharedFormatters.jsonDecoderSeconds.decode(T.self, from: data)
        } catch {
            throw AuthProxyError.decodeFailed
        }
    }
}
