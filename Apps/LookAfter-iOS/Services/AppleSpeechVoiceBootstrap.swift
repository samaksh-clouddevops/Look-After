import AVFoundation
import Foundation
import LookAfterCore

/// Prepares Apple voice metadata for executive speech without speaking at launch.
///
/// Important: `AVSpeechSynthesisVoice` / `speechVoices()` / `AVSpeechSynthesizer` must not be
/// touched from inside a Swift `Task` frame. On iOS 26 that path hits AXCoreUtilities
/// `unsafeForcedSync` and crashes with `__dispatch_assert_queue_fail`.
enum AppleSpeechVoiceBootstrap {

    private static var observerInstalled = false

    /// Safe to call from launch — hops onto GCD main before any speech API.
    static func startIfNeeded() {
        installVoiceChangeObserverIfNeeded()
        // Delay past first-frame SwiftUI/`Task` churn so voice APIs don't race concurrent TLS.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AppleSpeechVoiceCatalog.warmFromMainQueueIfNeeded()
        }
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
            DispatchQueue.main.async {
                AppleSpeechVoiceCatalog.warmFromMainQueueIfNeeded()
            }
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

    /// Safe from SwiftUI / Tasks — returns cache only; never calls into AX.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEnglish ?? []
    }

    /// Call only from GCD main outside a Swift `Task` (see bootstrap).
    static func warmFromMainQueueIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        if withUnsafeCurrentTask(body: { $0 != nil }) {
            // Still inside concurrency TLS — bounce once more onto pure GCD main.
            DispatchQueue.main.async {
                warmFromMainQueueIfNeeded()
            }
            return
        }

        lock.lock()
        if cachedEnglish != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }

        lock.lock()
        cachedEnglish = english
        lock.unlock()
    }
}
