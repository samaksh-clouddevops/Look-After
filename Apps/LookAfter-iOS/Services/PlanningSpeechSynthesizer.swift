import AVFoundation
import Foundation
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

    private let appleSynthesizer = AVSpeechSynthesizer()
    private let cloudPlayer = CloudSpeechPlayer()
    private var cloudTask: Task<Void, Never>?

    override init() {
        super.init()
        appleSynthesizer.delegate = self
        cloudPlayer.onFinished = { [weak self] in
            self?.isSpeaking = false
            VoiceSessionKeepAlive.end("speech-synthesis")
        }
        refreshActiveVoiceLabel()
    }

    func speak(_ text: String) {
        let prepared = SpeechTextPreprocessor.prepareForSpeech(text)
        guard !prepared.isEmpty else {
            isSpeaking = false
            return
        }

        stop()

        VoiceSessionKeepAlive.begin("speech-synthesis")

        if SpeechVoiceSettings.provider == .cloud, SpeechVoiceSettings.cloudAPIKey != nil {
            speakCloud(prepared)
            return
        }

        speakApple(prepared)
    }

    func stop() {
        cloudTask?.cancel()
        cloudTask = nil
        cloudPlayer.stop()
        if appleSynthesizer.isSpeaking || appleSynthesizer.isPaused {
            appleSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        VoiceSessionKeepAlive.end("speech-synthesis")
    }

    func previewSample() {
        speak("Here's how I sound. Calm, clear, and ready to help you plan the day.")
    }

    // MARK: - Cloud (OpenAI)

    private func speakCloud(_ text: String) {
        let voice = SpeechVoiceSettings.cloudVoice
        activeVoiceName = SpeechVoiceSettings.cloudVoices.first(where: { $0.id == voice })?.label ?? voice
        isSpeaking = true

        cloudTask = Task {
            do {
                let mp3 = try await OpenAICloudTTSService.synthesizeMP3(text: text)
                guard !Task.isCancelled else { return }
                try cloudPlayer.play(data: mp3)
            } catch {
                guard !Task.isCancelled else { return }
                print("[Speech] Cloud TTS failed: \(error.localizedDescription) — falling back to Apple")
                speakApple(text)
            }
        }
    }

    // MARK: - Apple

    private func speakApple(_ prepared: String) {
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
        activeVoiceName = voice?.name ?? "System"

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
        appleSynthesizer.speak(utterance)
    }

    private func refreshActiveVoiceLabel() {
        if SpeechVoiceSettings.provider == .cloud, SpeechVoiceSettings.cloudAPIKey != nil {
            let voice = SpeechVoiceSettings.cloudVoice
            activeVoiceName = SpeechVoiceSettings.cloudVoices.first(where: { $0.id == voice })?.label ?? voice
        } else {
            activeVoiceName = Self.resolveAppleVoice()?.name ?? "System"
        }
    }

    static func resolveVoice() -> AVSpeechSynthesisVoice? {
        resolveAppleVoice()
    }

    /// Prefer user choice → known premium/enhanced ids → best ranked voice → language default.
    static func resolveAppleVoice() -> AVSpeechSynthesisVoice? {
        if let id = SpeechVoiceSettings.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }

        let provider = SpeechVoiceSettings.provider
        let preferEnhanced = provider == .appleEnhanced || provider == .cloud

        if preferEnhanced {
            for identifier in SpeechVoiceSettings.preferredVoiceIdentifiers {
                if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                    return voice
                }
            }

            let english = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.language.lowercased().hasPrefix("en")
            }
            let ranked = english.sorted { lhs, rhs in
                voiceScore(lhs) > voiceScore(rhs)
            }
            if let best = ranked.first, voiceScore(best) >= 25 {
                return best
            }
        }

        if provider == .appleStandard,
           let english = AVSpeechSynthesisVoice.speechVoices().first(where: {
               $0.language.lowercased().hasPrefix("en") && !isCompactVoice($0)
           }) {
            return english
        }

        return AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
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

        if #available(iOS 16.0, macOS 13.0, *) {
            switch voice.quality {
            case .enhanced: score += 40
            case .premium: score += 60
            default: score += 5
            }
        } else {
            if id.contains("enhanced") || id.contains("premium") { score += 40 }
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
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
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
