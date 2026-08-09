import AVFoundation
import Foundation
import LookAfterCore
import LookAfterData

/// Natural speech via the licensed auth proxy (OpenAI TTS on the server).
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
                return "Cloud voice requires the Look After AI proxy."
            case .licenseRequired:
                return "Activate your product key in Settings → License to use cloud voice."
            case .emptyInput: return "Nothing to speak."
            case .badResponse(let detail): return "Cloud voice failed: \(detail)"
            case .playbackFailed(let detail): return "Could not play voice: \(detail)"
            }
        }
    }

    @MainActor
    static func synthesizeMP3(text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyInput }

        guard let proxy = LicenseManager.shared.proxyClient else {
            throw TTSError.proxyUnavailable
        }
        guard LicenseManager.shared.isLicensed else {
            throw TTSError.licenseRequired
        }

        return try await proxy.speech(
            input: String(trimmed.prefix(4096)),
            voice: SpeechVoiceSettings.cloudVoice,
            speed: cloudSpeed,
            model: "tts-1-hd"
        )
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
