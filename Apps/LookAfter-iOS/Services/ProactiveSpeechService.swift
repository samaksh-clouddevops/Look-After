import Foundation
import LookAfterCore
import LookAfterFeatures

@MainActor
final class ProactiveSpeechService {
    private let synthesizer: PlanningSpeechSynthesizer
    private static var lastSpokenKey: String?
    private static var lastSpokenAt: Date?
    private static let repeatCooldown: TimeInterval = 15 * 60

    init(synthesizer: PlanningSpeechSynthesizer) {
        self.synthesizer = synthesizer
    }

    func speakProactiveAction(_ action: ProactiveAction) {
        guard SpeechVoiceSettings.autoSpeakProactive || SpeechVoiceSettings.autoSpeakReplies else { return }
        guard action.severity == .high || action.kind == .initiationBridge || action.kind == .transitionShield else { return }
        let text = SpeechTextPreprocessor.prepareForSpeech(action.message)
        guard !text.isEmpty else { return }
        let key = "\(action.kind.rawValue)|\(action.message)"
        if Self.lastSpokenKey == key,
           let last = Self.lastSpokenAt,
           Date().timeIntervalSince(last) < Self.repeatCooldown {
            return
        }
        Self.lastSpokenKey = key
        Self.lastSpokenAt = Date()
        synthesizer.speak(text)
    }

    func speakNotificationBody(_ body: String) {
        guard SpeechVoiceSettings.autoSpeakProactive else { return }
        let text = SpeechTextPreprocessor.prepareForSpeech(body)
        guard !text.isEmpty else { return }
        if Self.lastSpokenKey == text,
           let last = Self.lastSpokenAt,
           Date().timeIntervalSince(last) < Self.repeatCooldown {
            return
        }
        Self.lastSpokenKey = text
        Self.lastSpokenAt = Date()
        synthesizer.speak(text)
    }
}
