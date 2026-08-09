import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct InitiationScriptSheet: View {
    let script: InitiationScript
    var speechSynthesizer: PlanningSpeechSynthesizer?
    let onStartFocus: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text(script.message)
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textSecondary)

                    Text("Micro-start (\(script.durationMinutes) min)")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)

                    ForEach(Array(script.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                            Text("\(index + 1)")
                                .font(.dsCaption(weight: .bold))
                                .foregroundColor(DesignSystem.accentPrimary)
                                .frame(width: 22, height: 22)
                                .background(DesignSystem.accentPrimary.opacity(0.15))
                                .clipShape(Circle())
                            Text(step)
                                .font(.dsBody())
                                .foregroundColor(DesignSystem.textPrimary)
                        }
                    }

                    if let speechSynthesizer {
                        Button {
                            let text = SpeechTextPreprocessor.prepareForSpeech(script.message + ". " + script.steps.joined(separator: ". "))
                            speechSynthesizer.speak(text)
                        } label: {
                            Label("Read aloud", systemImage: "speaker.wave.2.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: onStartFocus) {
                        Text("Start \(script.durationMinutes)-min focus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(DesignSystem.spacingLG)
            }
            .navigationTitle(script.taskTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: onDismiss)
                }
            }
        }
    }
}
