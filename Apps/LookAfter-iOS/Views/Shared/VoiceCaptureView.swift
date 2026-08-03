import SwiftUI
import LookAfterCore

/// Animated audio waveform visualization for voice capture.
struct AudioWaveformView: View {
    let levels: [CGFloat]
    var activeColor: Color = DesignSystem.accentPrimary
    var inactiveColor: Color = Color.white.opacity(0.15)
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.15 ? activeColor : inactiveColor)
                    .frame(width: 4, height: max(6, level * 40))
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 44)
    }
}

/// Reusable voice capture control with live transcription and waveform.
struct VoiceCaptureView: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Binding var text: String
    
    var body: some View {
        VStack(spacing: 12) {
            if speechManager.isListening {
                AudioWaveformView(levels: speechManager.audioLevels)
                    .padding(.horizontal, 8)
                
                if !speechManager.transcript.isEmpty {
                    Text(speechManager.transcript)
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
            }
            
            if let error = speechManager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DesignSystem.error)
                    Text(error)
                        .font(.system(size: 12, design: .default))
                        .foregroundColor(DesignSystem.error)
                }
            }
            
            Button(action: {
                HapticManager.impact(.medium)
                Task {
                    if speechManager.isListening {
                        speechManager.stopListening()
                        if !speechManager.transcript.isEmpty {
                            let prefix = text.isEmpty ? "" : " "
                            text += prefix + speechManager.transcript
                        }
                    } else {
                        await speechManager.startListening()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: speechManager.isListening ? "stop.circle.fill" : "mic.fill")
                    Text(speechManager.isListening ? "Stop Recording" : "Voice Capture")
                }
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(speechManager.isListening ? DesignSystem.error.opacity(0.85) : DesignSystem.accentPrimary)
                )
            }
        }
        .accessibilityIdentifier("screen-voice-capture")
    }
}
