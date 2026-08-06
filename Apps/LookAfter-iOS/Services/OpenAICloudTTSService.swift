import AVFoundation
import Foundation
import LookAfterCore

/// Natural speech via OpenAI's TTS API (tts-1-hd).
enum OpenAICloudTTSService {

    enum TTSError: LocalizedError {
        case missingAPIKey
        case emptyInput
        case badResponse(String)
        case playbackFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add an OpenAI API key in Settings → Voice & Speech, or set OPENAI_API_KEY."
            case .emptyInput: return "Nothing to speak."
            case .badResponse(let detail): return "Cloud voice failed: \(detail)"
            case .playbackFailed(let detail): return "Could not play voice: \(detail)"
            }
        }
    }

    static func synthesizeMP3(text: String) async throws -> Data {
        guard let apiKey = SpeechVoiceSettings.cloudAPIKey else { throw TTSError.missingAPIKey }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyInput }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": String(trimmed.prefix(4096)),
            "voice": SpeechVoiceSettings.cloudVoice,
            "response_format": "mp3",
            "speed": cloudSpeed,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TTSError.badResponse("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TTSError.badResponse(snippet)
        }
        guard !data.isEmpty else { throw TTSError.badResponse("Empty audio") }
        return data
    }

    /// Maps user rate preference (0.35…0.65) into OpenAI's 0.25…4.0 speed band.
    private static var cloudSpeed: Double {
        let pref = SpeechVoiceSettings.rate
        let normalized = (pref - 0.35) / 0.30
        return min(max(0.85 + normalized * 0.25, 0.75), 1.15)
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

    var isPlaying: Bool { player?.isPlaying == true }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            onFinished?()
        }
    }
}
