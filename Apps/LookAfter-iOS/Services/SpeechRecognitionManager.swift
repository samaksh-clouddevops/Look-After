import Foundation
import AVFoundation
import Speech
import Combine

/// Production speech-to-text service using Apple's SFSpeechRecognizer and AVAudioEngine.
@MainActor
public final class SpeechRecognitionManager: ObservableObject {
    
    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false
    @Published public var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
    @Published public var permissionDenied: Bool = false
    @Published public var errorMessage: String?
    
    /// When enabled, fires `onUtteranceComplete` after silence or a final recognition result.
    public var autoCommitEnabled = false
    /// Seconds of silence after speech before auto-committing the transcript.
    public var autoCommitSilenceDuration: TimeInterval = 1.8
    /// Called once per utterance with the final transcript (auto-commit or manual stop).
    public var onUtteranceComplete: ((String) -> Void)?
    
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var levelTimer: Timer?
    private var silenceTimer: Timer?
    private var lastTranscriptChange = Date()
    private var hasReceivedSpeech = false
    private var utteranceCommitted = false
    /// Throttle MainActor hops from the audio tap (BUG-019).
    private var lastLevelPublish = Date.distantPast
    private let levelPublishInterval: TimeInterval = 0.05

    public init() {
        let preferred = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0) } ?? Locale.current
        if let recognizer = SFSpeechRecognizer(locale: preferred), recognizer.isAvailable {
            speechRecognizer = recognizer
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }
    
    /// Request microphone and speech recognition permissions.
    public func requestPermissions() async -> Bool {
        let speechStatus = await Self.requestSpeechAuthorization()
        
        guard speechStatus == .authorized else {
            permissionDenied = true
            errorMessage = "Speech recognition permission was denied."
            return false
        }
        
        #if os(iOS)
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            permissionDenied = true
            errorMessage = "Microphone permission was denied."
            return false
        }
        #endif
        
        return true
    }

    /// Speech authorization is delivered on a system queue. Keep this off the main actor or opening Brain traps.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// The audio tap runs on the audio thread, not the main actor.
    nonisolated private static func installRecognitionTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        owner: SpeechRecognitionManager
    ) {
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<frameLength {
                sum += abs(channelData[index])
            }
            let average = sum / Float(frameLength)
            let level = CGFloat(min(average * 8, 1.0))
            Task { @MainActor in
                owner.applyAudioLevel(level)
            }
        }
    }

    /// Recognition results arrive off the main actor.
    nonisolated private static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        owner: SpeechRecognitionManager
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                owner.handleRecognition(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    private func applyAudioLevel(_ level: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelPublish) >= levelPublishInterval else { return }
        lastLevelPublish = now
        updateAudioLevels(level: level)
    }

    private func handleRecognition(text: String?, isFinal: Bool, failed: Bool) {
        if let text {
            transcript = text
            noteTranscriptActivity()
        }
        if isFinal {
            if autoCommitEnabled {
                completeUtterance()
            } else {
                stopListening()
            }
        } else if failed {
            if autoCommitEnabled, hasReceivedSpeech {
                completeUtterance()
            } else {
                stopListening()
            }
        }
    }
    
    /// Start live speech recognition with real-time transcription.
    public func startListening() async {
        guard !isListening else { return }
        
        if permissionDenied { return }
        
        let authorized = await requestPermissions()
        guard authorized else { return }
        
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }
        
        stopListening(resetTranscript: false)
        transcript = ""
        errorMessage = nil
        utteranceCommitted = false
        hasReceivedSpeech = false
        lastTranscriptChange = Date()
        
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            VoiceSessionKeepAlive.begin("speech-recognition")
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            // Capture locally so the audio tap never touches MainActor-isolated state.
            let requestForTap = recognitionRequest
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                errorMessage = "Microphone is not available right now."
                stopListening()
                return
            }

            Self.installRecognitionTap(
                on: inputNode,
                format: recordingFormat,
                request: requestForTap,
                owner: self
            )

            recognitionTask = Self.startRecognitionTask(
                recognizer: speechRecognizer,
                request: recognitionRequest,
                owner: self
            )
            
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startLevelAnimation()
            if autoCommitEnabled {
                startSilenceMonitoring()
            }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            stopListening()
        }
    }
    
    /// Stop speech recognition and release audio resources.
    public func stopListening(resetTranscript: Bool = true) {
        levelTimer?.invalidate()
        levelTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        isListening = false
        audioLevels = Array(repeating: 0.1, count: 20)
        if resetTranscript {
            hasReceivedSpeech = false
        }

        VoiceSessionKeepAlive.end("speech-recognition")

        VoiceSessionKeepAlive.end("speech-recognition")

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    
    private func updateAudioLevels(level: CGFloat) {
        let next = max(0.08, level)
        // Avoid publishing identical-looking bars (PERF-004).
        var levels = audioLevels
        levels.removeFirst()
        levels.append(next)
        audioLevels = levels
    }

    private func startLevelAnimation() {
        levelTimer?.invalidate()
        // 10 Hz is enough for visualizers; 20 Hz was thrashing @Published (PERF-004).
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                // Subtle idle animation when levels are low
                if self.audioLevels.allSatisfy({ $0 < 0.15 }) {
                    self.audioLevels = self.audioLevels.map { _ in CGFloat.random(in: 0.08...0.2) }
                }
            }
        }
        levelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func noteTranscriptActivity() {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasReceivedSpeech = true
        lastTranscriptChange = Date()
    }

    private func startSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSilenceTimeout()
            }
        }
    }

    private func checkSilenceTimeout() {
        guard isListening, autoCommitEnabled, hasReceivedSpeech, !utteranceCommitted else { return }
        let elapsed = Date().timeIntervalSince(lastTranscriptChange)
        if elapsed >= autoCommitSilenceDuration {
            completeUtterance()
        }
    }

    private func completeUtterance() {
        guard isListening, !utteranceCommitted else { return }
        utteranceCommitted = true
        silenceTimer?.invalidate()
        silenceTimer = nil

        let message = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening(resetTranscript: false)
        onUtteranceComplete?(message)
    }

    private func noteTranscriptActivity() {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasReceivedSpeech = true
        lastTranscriptChange = Date()
    }

    private func startSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSilenceTimeout()
            }
        }
    }

    private func checkSilenceTimeout() {
        guard isListening, autoCommitEnabled, hasReceivedSpeech, !utteranceCommitted else { return }
        let elapsed = Date().timeIntervalSince(lastTranscriptChange)
        if elapsed >= autoCommitSilenceDuration {
            completeUtterance()
        }
    }

    private func completeUtterance() {
        guard isListening, !utteranceCommitted else { return }
        utteranceCommitted = true
        silenceTimer?.invalidate()
        silenceTimer = nil

        let message = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening(resetTranscript: false)
        onUtteranceComplete?(message)
    }
}
