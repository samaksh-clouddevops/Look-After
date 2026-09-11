import AVFoundation
import Foundation
import LookAfterAI
import LookAfterCore
import LookAfterData

/// Natural speech via OpenAI TTS — prefers a local API key; falls back to licensed auth-proxy.
enum OpenAICloudTTSService {

    enum TTSError: LocalizedError {
        case proxyUnavailable
        case licenseRequired
        case emptyInput
        case badResponse(String)
        case playbackFailed(String)

        var errorDescription: String? {
            switch self {
            case .proxyUnavailable:
                return "Cloud voice needs an OpenAI API key in credentials, or the Look After AI proxy."
            case .licenseRequired:
                return "Activate your product key in Settings → License to use proxied cloud voice."
            case .emptyInput: return "Nothing to speak."
            case .badResponse(let detail): return "Cloud voice failed: \(detail)"
            case .playbackFailed(let detail): return "Could not play voice: \(detail)"
            }
        }
    }

    static func synthesizeMP3(text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyInput }

        let input = String(trimmed.prefix(4096))
        let voice = await MainActor.run { SpeechVoiceSettings.cloudVoice }
        let speed = await MainActor.run { cloudSpeed }

        if let apiKey = GLMKeyManager.resolveOpenAIAPIKey() {
            await MainActor.run { SpeechVoiceSettings.isOpenAIKeyConfigured = true }
            return try await synthesizeDirect(
                apiKey: apiKey,
                input: input,
                voice: voice,
                speed: speed
            )
        }

        let proxyClient = await MainActor.run { LicenseManager.shared.proxyClient }
        let licensed = await MainActor.run { LicenseManager.shared.isLicensed }
        guard let proxy = proxyClient else {
            throw TTSError.proxyUnavailable
        }
        guard licensed else {
            throw TTSError.licenseRequired
        }

        return try await proxy.speech(
            input: input,
            voice: voice,
            speed: speed,
            model: "tts-1-hd"
        )
    }

    /// Maps user rate preference (0.35…0.65) into OpenAI's 0.25…4.0 speed band.
    @MainActor
    private static var cloudSpeed: Double {
        let pref = SpeechVoiceSettings.rate
        let normalized = (pref - 0.35) / 0.30
        return min(max(0.85 + normalized * 0.25, 0.75), 1.15)
    }

    private static func synthesizeDirect(
        apiKey: String,
        input: String,
        voice: String,
        speed: Double
    ) async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw TTSError.badResponse("Invalid OpenAI URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "tts-1-hd",
            "input": input,
            "voice": voice,
            "response_format": "mp3",
            "speed": speed
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TTSError.badResponse("Invalid response")
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            throw TTSError.badResponse("HTTP \(http.statusCode) \(snippet)")
        }
        guard !data.isEmpty else {
            throw TTSError.badResponse("Empty audio")
        }
        return data
    }
}

/// Plays MP3 bytes from cloud TTS.
@MainActor
final class CloudSpeechPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onFinished: (() -> Void)?

    func play(data: Data) throws {
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        guard player?.play() == true else {
            throw OpenAICloudTTSService.TTSError.playbackFailed("AVAudioPlayer refused to start")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.onFinished?()
        }
    }
}
