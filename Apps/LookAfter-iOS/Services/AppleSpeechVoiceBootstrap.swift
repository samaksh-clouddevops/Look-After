import AVFoundation
import Foundation
import LookAfterCore

/// Silently prepares Apple Enhanced/Premium voices for executive speech.
///
/// iOS has no public API to download Enhanced/Premium voice assets in the background.
/// This service warms up the best installed voice and re-warms when the system voice set changes
/// (e.g. after the user downloads voices in Settings).
///
/// Important: `AVSpeechSynthesisVoice` / `speechVoices()` / `AVSpeechSynthesizer` must not be
/// touched from inside a Swift `Task` frame. On iOS 26 that path hits AXCoreUtilities
/// `unsafeForcedSync` and logs "Potential Structural Swift Concurrency Issue".
enum AppleSpeechVoiceBootstrap {

    private static var observerInstalled = false

    /// Safe to call from a Swift `Task` — hops onto the main queue outside concurrency TLS
    /// before any AVSpeech voice API runs.
    static func startIfNeeded() {
        installVoiceChangeObserverIfNeeded()
        DispatchQueue.main.async {
            kickoffWarmupOnMainQueue()
        }
    }

    /// Runs on the main queue (GCD), not inside a Swift Task.
    private static func kickoffWarmupOnMainQueue() {
        guard let voice = resolveWarmupVoice() else { return }
        // Only the continuation wait is async; synthesizer construction stays off the Task frame.
        Task { @MainActor in
            await synthesizeWarmupEscapingTask(with: voice)
        }
    }

    private static func resolveWarmupVoice() -> AVSpeechSynthesisVoice? {
        for identifier in SpeechVoiceSettings.preferredVoiceIdentifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
        }

        let english = AppleSpeechVoiceCatalog.englishVoices()
        if let best = english.max(by: { score($0) < score($1) }), score(best) >= 25 {
            return best
        }
        return nil
    }

    @MainActor
    private static var activeWarmup: WarmupSession?

    /// Creates the synthesizer via GCD so we leave the Swift Task execution frame first.
    @MainActor
    private static func synthesizeWarmupEscapingTask(with voice: AVSpeechSynthesisVoice) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                let session = WarmupSession(voice: voice) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            activeWarmup = nil
                        }
                        continuation.resume()
                    }
                }
                MainActor.assumeIsolated {
                    activeWarmup = session
                }
            }
        }
    }

    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        var value = 0
        let id = voice.identifier.lowercased()
        switch voice.quality {
        case .premium: value += 60
        case .enhanced: value += 40
        default: value += 5
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
            AppleSpeechVoiceCatalog.invalidate()
            // GCD main queue — not Task { } — before touching voice APIs.
            DispatchQueue.main.async {
                kickoffWarmupOnMainQueue()
            }
        }
    }

    /// Speech engine callbacks are off the main actor; keep finish path thread-safe.
    private final class WarmupSession: NSObject, AVSpeechSynthesizerDelegate {
        private let synthesizer = AVSpeechSynthesizer()
        private let onFinish: @Sendable () -> Void
        private let finishLock = NSLock()
        private var didFinish = false

        init(voice: AVSpeechSynthesisVoice, onFinish: @escaping @Sendable () -> Void) {
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

        nonisolated private func finishOnce() {
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            onFinish()
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            finishOnce()
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            finishOnce()
        }
    }
}

/// Cached `speechVoices()` results so Settings / TTS resolve don't re-enter AX repeatedly.
enum AppleSpeechVoiceCatalog {
    private static let lock = NSLock()
    private static var cachedEnglish: [AVSpeechSynthesisVoice]?

    static func invalidate() {
        lock.lock()
        cachedEnglish = nil
        lock.unlock()
    }

    /// Prefer calling from the main queue outside a Swift `Task` (see bootstrap).
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        lock.lock()
        if let cachedEnglish {
            lock.unlock()
            return cachedEnglish
        }
        lock.unlock()

        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }

        lock.lock()
        cachedEnglish = english
        lock.unlock()
        return english
    }
}
