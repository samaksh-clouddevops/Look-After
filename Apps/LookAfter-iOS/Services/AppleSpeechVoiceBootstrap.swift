import AVFoundation
import Foundation
import LookAfterCore

/// Silently prepares Apple Enhanced/Premium voices for executive speech.
///
/// iOS has no public API to download Enhanced/Premium voice assets in the background.
/// This service warms up the best installed voice and re-warms when the system voice set changes
/// (e.g. after the user downloads voices in Settings).
enum AppleSpeechVoiceBootstrap {

    private static var observerInstalled = false

    static func startIfNeeded() {
        installVoiceChangeObserverIfNeeded()
        Task { @MainActor in
            await warmPreferredVoices()
        }
    }

    @MainActor
    private static func warmPreferredVoices() async {
        for identifier in SpeechVoiceSettings.preferredVoiceIdentifiers {
            guard let voice = AVSpeechSynthesisVoice(identifier: identifier) else { continue }
            await synthesizeWarmup(with: voice)
            return
        }

        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("en")
        }
        if let best = english.max(by: { score($0) < score($1) }), score(best) >= 25 {
            await synthesizeWarmup(with: best)
        }
    }

    @MainActor
    private static var activeWarmup: WarmupSession?

    @MainActor
    private static func synthesizeWarmup(with voice: AVSpeechSynthesisVoice) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            activeWarmup = WarmupSession(voice: voice) {
                activeWarmup = nil
                continuation.resume()
            }
        }
    }

    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        var value = 0
        let id = voice.identifier.lowercased()
        if #available(iOS 16.0, *) {
            switch voice.quality {
            case .premium: value += 60
            case .enhanced: value += 40
            default: value += 5
            }
        } else if id.contains("enhanced") || id.contains("premium") {
            value += 40
        }
        if id.contains("compact") { value -= 80 }
        if voice.language.lowercased().hasPrefix("en-us") { value += 10 }
        return value
    }

    private static func installVoiceChangeObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await warmPreferredVoices()
            }
        }
    }

    @MainActor
    private final class WarmupSession: NSObject, AVSpeechSynthesizerDelegate {
        private let synthesizer = AVSpeechSynthesizer()
        private let onFinish: () -> Void

        init(voice: AVSpeechSynthesisVoice, onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
            super.init()
            synthesizer.delegate = self

            let utterance = AVSpeechUtterance(string: ".")
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceMinimumSpeechRate
            utterance.volume = 0.01
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0
            synthesizer.speak(utterance)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onFinish()
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onFinish()
        }
    }
}
