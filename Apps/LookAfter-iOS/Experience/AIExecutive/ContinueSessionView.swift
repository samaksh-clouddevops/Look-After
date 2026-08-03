import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Continue — restoration through context, then explicit Continue Working.
struct ContinueSessionView: View {
    @ObservedObject var controller: ContinueSessionController
    var onOpenHealth: () -> Void
    var onDone: () -> Void

    @State private var restoreProgress: Double = 0
    @State private var restorationToken = UUID()

    var body: some View {
        ZStack {
            CinematicBackground(accentIntensity: 0.18)

            if let context = controller.context {
                switch controller.phase {
                case .restoring:
                    restoringWorld(context)
                case .workspace, .active:
                    workspaceWorld(context)
                case .failed:
                    failedWorld(context)
                }
            }
        }
        .onAppear { startRestorationAnimation() }
        .onChange(of: controller.isPresented) { _, isPresented in
            guard isPresented else { return }
            restorationToken = UUID()
            startRestorationAnimation()
        }
        .id(restorationToken)
    }

    private func restoringWorld(_ context: ContinueSessionContext) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VisualMemoryCanvas(
                context: context.workingContext,
                resume: context.resumeSnapshot,
                task: context.task,
                progress: restoreProgress
            )
            .padding(.horizontal, 16)
            .scaleEffect(0.92 + restoreProgress * 0.08)
            .opacity(0.45 + restoreProgress * 0.55)

            MeaningfulProgressView(
                heading: context.restorationMessage.isEmpty ? "Restoring your workspace…" : context.restorationMessage,
                steps: context.restorationSteps.isEmpty
                    ? HumanLanguage.restorationSteps(for: context.workingContext, resume: context.resumeSnapshot, task: context.task)
                    : context.restorationSteps,
                progress: restoreProgress
            )
            .padding(.top, 40)

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func workspaceWorld(_ context: ContinueSessionContext) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DesignSystem.textMuted)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                if controller.hasUserStartedWork {
                    Text(controller.elapsedLabel)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.accentPrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VisualMemoryCanvas(
                context: context.workingContext,
                resume: context.resumeSnapshot,
                task: context.task
            )
            .padding(.horizontal, 16)

            Spacer()

            if controller.phase == .workspace {
                ImmersivePrimaryCTA("Continue Working") {
                    HapticManager.impact(.medium)
                    controller.beginWork()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            } else {
                Button("Done") { onDone() }
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .padding(.bottom, 48)
            }
        }
        .transition(.opacity)
    }

    private func failedWorld(_ context: ContinueSessionContext) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Text(controller.restorationError ?? "We couldn't restore your previous workspace.")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 14) {
                if context.task != nil {
                    Button("Open Task") {
                        HapticManager.impact(.light)
                        controller.finishRestoring()
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(DesignSystem.accentPrimary)
                }

                if context.resumeSnapshot?.lastNote != nil {
                    Button("Open Notes") {
                        HapticManager.impact(.light)
                        controller.finishRestoring()
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(DesignSystem.textSecondary)
                }

                Button("Go Home") {
                    HapticManager.impact(.light)
                    onDone()
                }
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(DesignSystem.textMuted)
            }

            Spacer()
        }
        .padding(.bottom, 48)
    }

    private func startRestorationAnimation() {
        guard controller.phase == .restoring else { return }
        restoreProgress = 0
        let seconds = max(0.5, Double(controller.context?.restartTaxSeconds ?? 1))
        withAnimation(.easeInOut(duration: seconds)) { restoreProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard controller.phase == .restoring else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                controller.finishRestoring()
            }
        }
    }
}
