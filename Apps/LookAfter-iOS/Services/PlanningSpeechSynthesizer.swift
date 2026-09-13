import AVFoundation
import Foundation
import LookAfterAI
import LookAfterCore

// MARK: - Protocol

/// Abstraction over local Apple TTS and cloud neural TTS.
@MainActor
protocol SpeechSynthesizing: AnyObject, ObservableObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
    func stop()
}

// MARK: - Router implementation

/// Executive speech — Apple on-device or OpenAI cloud neural voice.
@MainActor
final class PlanningSpeechSynthesizer: NSObject, ObservableObject, SpeechSynthesizing {
    @Published private(set) var isSpeaking = false
    @Published private(set) var activeVoiceName: String = ""
    /// Last cloud TTS failure (cleared on successful speak). Shown in Settings preview.
    @Published private(set) var lastError: String?

    /// Lazily created on GCD main — never from a property initializer inside a SwiftUI/`Task` frame
    /// (iOS 26 AX `unsafeForcedSync` / `__dispatch_assert_queue_fail`).
    private var appleSynthesizer: AVSpeechSynthesizer?
    private let cloudPlayer = CloudSpeechPlayer()
    private var cloudTask: Task<Void, Never>?

    override init() {
        super.init()
        cloudPlayer.onFinished = { [weak self] in
            self?.isSpeaking = false
            VoiceSessionKeepAlive.end("speech-synthesis")
        }
        // Resolve voice labels on the main queue outside any caller Task frame.
        DispatchQueue.main.async { [weak self] in
            self?.refreshActiveVoiceLabel()
        }
    }

    private func ensureAppleSynthesizer() -> AVSpeechSynthesizer {
        if let appleSynthesizer { return appleSynthesizer }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        appleSynthesizer = synthesizer
        return synthesizer
    }

    func speak(_ text: String) {
        let prepared = SpeechTextPreprocessor.prepareForSpeech(text)
        guard !prepared.isEmpty else {
            isSpeaking = false
            return
        }

        stop()
        lastError = nil

        VoiceSessionKeepAlive.begin("speech-synthesis")

        if SpeechVoiceSettings.provider == .cloud {
            speakCloud(prepared)
            return
        }

        // Escape Swift concurrency TLS before AVSpeech (same pattern as AppleSpeechVoiceBootstrap).
        DispatchQueue.main.async { [weak self] in
            self?.speakApple(prepared)
        }
    }

    func stop() {
        cloudTask?.cancel()
        cloudTask = nil
        cloudPlayer.stop()
        if let appleSynthesizer, appleSynthesizer.isSpeaking || appleSynthesizer.isPaused {
            appleSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        VoiceSessionKeepAlive.end("speech-synthesis")
    }

    func previewSample() {
        // Ensure OpenAI key is synced before preview (simulator/device credentials).
        _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
        speak("Here's how I sound. Calm, clear, and ready to help you plan the day.")
    }

    // MARK: - Cloud (OpenAI)

    private func speakCloud(_ text: String) {
        let voice = SpeechVoiceSettings.cloudVoice
        activeVoiceName = SpeechVoiceSettings.cloudVoices.first(where: { $0.id == voice })?.label ?? voice
        isSpeaking = true

        cloudTask = Task { @MainActor in
            do {
                // Refresh key from credentials/Keychain right before the request.
                _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
                let mp3 = try await OpenAICloudTTSService.synthesizeMP3(text: text)
                guard !Task.isCancelled else { return }
                try cloudPlayer.play(data: mp3)
                lastError = nil
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                lastError = message
                print("[Speech] Cloud TTS failed: \(message) — falling back to Apple")
                activeVoiceName = "System (cloud failed)"
                DispatchQueue.main.async { [weak self] in
                    self?.speakApple(text, preserveActiveVoiceName: true)
                }
            }
        }
    }

    // MARK: - Apple

    private func speakApple(_ prepared: String, preserveActiveVoiceName: Bool = false) {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isSpeaking = false
            VoiceSessionKeepAlive.end("speech-synthesis")
            return
        }
        #endif

        let utterance = AVSpeechUtterance(string: prepared)
        let voice = Self.resolveAppleVoice()
        utterance.voice = voice
        if !preserveActiveVoiceName {
            activeVoiceName = voice?.name ?? "System"
        }

        let prefRate = Float(SpeechVoiceSettings.rate)
        let minRate = AVSpeechUtteranceMinimumSpeechRate
        let maxRate = AVSpeechUtteranceMaximumSpeechRate
        let defaultRate = AVSpeechUtteranceDefaultSpeechRate
        let rateBlend = (prefRate - 0.35) / 0.30 * 0.30
        let target = defaultRate * (0.85 + rateBlend)
        utterance.rate = min(max(target, minRate), maxRate)
        utterance.pitchMultiplier = Float(SpeechVoiceSettings.pitch)
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.08

        isSpeaking = true
        ensureAppleSynthesizer().speak(utterance)
    }

    private func refreshActiveVoiceLabel() {
        if SpeechVoiceSettings.provider == .cloud {
            let voice = SpeechVoiceSettings.cloudVoice
            activeVoiceName = SpeechVoiceSettings.cloudVoices.first(where: { $0.id == voice })?.label ?? voice
        } else {
            // Voice lookup can touch AX — keep on GCD main async path only.
            activeVoiceName = Self.resolveAppleVoice()?.name ?? "System"
        }
    }

    static func resolveVoice() -> AVSpeechSynthesisVoice? {
        resolveAppleVoice()
    }

    /// Prefer user choice → known premium/enhanced ids → best ranked voice → language default.
    /// Voice object creation stays on the GCD speak path; catalog reads are cache-only.
    static func resolveAppleVoice() -> AVSpeechSynthesisVoice? {
        let english = AppleSpeechVoiceCatalog.englishVoices()

        if let id = SpeechVoiceSettings.voiceIdentifier,
           let chosen = english.first(where: { $0.identifier == id }) {
            return chosen
        }

        let provider = SpeechVoiceSettings.provider
        let preferEnhanced = provider == .appleEnhanced || provider == .cloud

        if preferEnhanced {
            for identifier in SpeechVoiceSettings.preferredVoiceIdentifiers {
                if let voice = english.first(where: { $0.identifier == identifier }) {
                    return voice
                }
            }

            let ranked = english.sorted { lhs, rhs in
                voiceScore(lhs) > voiceScore(rhs)
            }
            if let best = ranked.first, voiceScore(best) >= 25 {
                return best
            }
        }

        if provider == .appleStandard,
           let englishVoice = english.first(where: { !isCompactVoice($0) }) {
            return englishVoice
        }

        return english.first
    }

    private static func isCompactVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let id = voice.identifier.lowercased()
        let name = voice.name.lowercased()
        return id.contains("compact") || name.contains("compact")
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        let id = voice.identifier.lowercased()
        let name = voice.name.lowercased()

        switch voice.quality {
        case .enhanced: score += 40
        case .premium: score += 60
        default: score += 5
        }

        if id.contains("compact") || name.contains("compact") { score -= 80 }

        let preferredTokens = [
            "samantha", "nora", "zoe", "ava", "allison", "susan", "karen",
            "daniel", "moira", "tessa", "siri", "nicky", "aaron"
        ]
        if preferredTokens.contains(where: { name.contains($0) || id.contains($0) }) {
            score += 25
        }

        if voice.language.lowercased().hasPrefix("en-us") { score += 10 }
        else if voice.language.lowercased().hasPrefix("en") { score += 5 }

        if name.contains("whisper") || name.contains("bad news") || name.contains("organ") {
            score -= 50
        }
        return score
    }

    static func availableEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AppleSpeechVoiceCatalog.englishVoices()
            .sorted {
                if voiceScore($0) != voiceScore($1) { return voiceScore($0) > voiceScore($1) }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Apple delegate

extension PlanningSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            VoiceSessionKeepAlive.end("speech-synthesis")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            VoiceSessionKeepAlive.end("speech-synthesis")
        }
    }
}
