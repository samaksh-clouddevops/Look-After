import AVFoundation
import Foundation
import LookAfterCore

// MARK: - Protocol

/// Abstraction over local Apple TTS and future cloud providers.
@MainActor
protocol SpeechSynthesizing: AnyObject, ObservableObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
    func stop()
}

// MARK: - Apple implementation

/// Executive-grade text-to-speech: preprocess → enhanced Apple voice → warm delivery.
@MainActor
final class PlanningSpeechSynthesizer: NSObject, ObservableObject, SpeechSynthesizing {
    @Published private(set) var isSpeaking = false
    /// Last voice identifier successfully used (for Settings diagnostics / preview).
    @Published private(set) var activeVoiceName: String = ""

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
        activeVoiceName = Self.resolveVoice()?.name ?? "System"
    }

    /// Preprocess markdown/lists/abbreviations, then speak with the preferred Apple voice.
    func speak(_ text: String) {
        let prepared = SpeechTextPreprocessor.prepareForSpeech(text)
        guard !prepared.isEmpty else {
            isSpeaking = false
            return
        }

        stop()

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Leave any mic `.record` session left by speech recognition.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isSpeaking = false
            return
        }
        #endif

        let utterance = AVSpeechUtterance(string: prepared)
        let voice = Self.resolveVoice()
        utterance.voice = voice
        activeVoiceName = voice?.name ?? "System"

        // Map 0.35…0.65 preference into a calm AVSpeech band around default.
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
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// Preview current settings with a short sample.
    func previewSample() {
        speak("Here's how I sound. Calm, clear, and ready to help you plan the day.")
    }

    // MARK: - Voice resolution

    /// Prefer user choice → enhanced Siri/premium en voices → en-US quality → language default.
    static func resolveVoice() -> AVSpeechSynthesisVoice? {
        if let id = SpeechVoiceSettings.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }

        let provider = SpeechVoiceSettings.provider
        // Cloud is not wired yet — fall back to enhanced Apple.
        let preferEnhanced = provider == .appleEnhanced || provider == .cloud

        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("en")
        }

        if preferEnhanced {
            // Prefer higher quality / premium voices when installed.
            let ranked = english.sorted { lhs, rhs in
                voiceScore(lhs) > voiceScore(rhs)
            }
            if let best = ranked.first, voiceScore(best) > 0 {
                return best
            }
        }

        return AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? english.first
    }

    /// Higher = warmer / more natural executive voice.
    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        let id = voice.identifier.lowercased()
        let name = voice.name.lowercased()

        // Quality API (iOS 16+)
        if #available(iOS 16.0, macOS 13.0, *) {
            switch voice.quality {
            case .enhanced: score += 40
            case .premium: score += 60
            default: score += 5
            }
        } else {
            if id.contains("enhanced") || id.contains("premium") { score += 40 }
        }

        // Known natural Siri / neural-ish English voices.
        let preferredTokens = [
            "samantha", "nora", "zoe", "ava", "allison", "susan", "karen",
            "daniel", "moira", "tessa", "siri", "nicky", "aaron"
        ]
        if preferredTokens.contains(where: { name.contains($0) || id.contains($0) }) {
            score += 25
        }

        if voice.language.lowercased().hasPrefix("en-us") { score += 10 }
        else if voice.language.lowercased().hasPrefix("en") { score += 5 }

        // Slight preference against novelty / novelty-character voices.
        if name.contains("whisper") || name.contains("bad news") || name.contains("organ") {
            score -= 50
        }
        return score
    }

    /// Catalog of English voices for Settings pickers.
    static func availableEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted {
                if voiceScore($0) != voiceScore($1) { return voiceScore($0) > voiceScore($1) }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Delegate

extension PlanningSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
