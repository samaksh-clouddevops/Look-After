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

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var levelTimer: Timer?
    /// Latest RMS from the audio tap — read on the main timer, not per buffer.
    private nonisolated(unsafe) var pendingAudioLevel: CGFloat = 0.1

    public init() {}

    deinit {
        levelTimer?.invalidate()
    }

    /// Request microphone and speech recognition permissions.
    public func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            permissionDenied = true
            errorMessage = "Speech recognition permission was denied."
            return false
        }

        #if os(iOS)
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micGranted else {
            permissionDenied = true
            errorMessage = "Microphone permission was denied."
            return false
        }
        #endif

        return true
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

        stopListening()
        transcript = ""
        errorMessage = nil
        pendingAudioLevel = 0.1

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)

                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(channelData[i])
                }
                let avg = sum / Float(max(frameLength, 1))
                self?.pendingAudioLevel = CGFloat(min(avg * 8, 1.0))
            }

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.transcript = text
                        if result.isFinal {
                            self.stopListening()
                        }
                    }
                }
                if error != nil {
                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startLevelAnimation()

        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            stopListening()
        }
    }

    /// Stop speech recognition and release audio resources.
    public func stopListening() {
        levelTimer?.invalidate()
        levelTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        pendingAudioLevel = 0.1

        audioLevels = Array(repeating: 0.1, count: 20)

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func updateAudioLevels(level: CGFloat) {
        audioLevels.removeFirst()
        audioLevels.append(max(0.08, level))
    }

    private func startLevelAnimation() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isListening else { return }
                let level = self.pendingAudioLevel
                if level > 0.15 {
                    self.updateAudioLevels(level: level)
                } else if self.audioLevels.allSatisfy({ $0 < 0.15 }) {
                    self.audioLevels = self.audioLevels.map { _ in CGFloat.random(in: 0.08...0.2) }
                }
            }
        }
    }
}
