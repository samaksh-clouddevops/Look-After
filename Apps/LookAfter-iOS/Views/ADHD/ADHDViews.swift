import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Emergency Mode — shows only top 3 tasks with large tap targets, minimal UI.
/// Designed for overwhelm moments when the user needs maximum simplicity.
struct EmergencyModeView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    let onStartTask: (LifeTask) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: DesignSystem.spacingXL) {
                Spacer()
                
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.textSecondary)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    
                    Text("Emergency Mode")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Text("Just pick one. That's all you need to do.")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Top 3 tasks as large buttons
                VStack(spacing: DesignSystem.spacingMD) {
                    ForEach(Array(adhdVM.emergencyTasks.enumerated()), id: \.element.id) { index, task in
                        Button(action: { onStartTask(task) }) {
                            HStack(spacing: DesignSystem.spacingMD) {
                                Text("\(index + 1)")
                                    .font(.system(size: 24, weight: .bold, design: .default))
                                    .foregroundColor(DesignSystem.accentPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.accentPrimary.opacity(0.2))
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .font(.system(size: 18, weight: .semibold, design: .default))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text("~\(task.estimatedMinutes) min • \(task.lifeArea.rawValue)")
                                        .font(.system(size: 13, weight: .medium, design: .default))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(DesignSystem.spacingMD)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusLG)
                                    .fill(DesignSystem.contentSurfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusLG)
                                            .stroke(DesignSystem.border, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.spacingMD)
                
                Spacer()
                
                // Exit button
                Button(action: { adhdVM.deactivateEmergencyMode() }) {
                    Text("Exit Emergency Mode")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.5))
                }
                .accessibilityLabel("Exit emergency mode")
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .accessibilityIdentifier("screen-emergency")
    }
}

/// Focus Session View — timer with progress ring, pause/resume, breaks, and duration controls.
struct FocusSessionView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDurationPicker = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 40
    
    private var accent: Color {
        adhdVM.isOnBreak ? DesignSystem.textSecondary : DesignSystem.accentPrimary
    }

    var body: some View {
        ZStack {
            // Premium dark canvas — deliberately forced dark regardless of system
            // appearance so the focus clock reads as a calm, immersive instrument.
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [accent.opacity(0.10), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: DesignSystem.spacingLG) {
                Spacer(minLength: DesignSystem.spacingLG)

                // Session state label
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                    Text(adhdVM.sessionLabel.uppercased())
                        .font(.dsMetadata(weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(accent)
                    Text("•")
                        .foregroundColor(.white.opacity(0.3))
                    Text(adhdVM.sessionCounterString)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.06)))

                // Task name
                if let task = adhdVM.currentFocusTask {
                    Text(task.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal)
                }

                Spacer(minLength: DesignSystem.spacingSM)

                // Timer ring + analog clock (+ PhaseAnimator breathe when motion allowed)
                ZStack {
                    focusBreatheGlow

                    AnalogFocusClockView(
                        progress: adhdVM.focusProgress,
                        accentColor: accent,
                        trackColor: Color.white.opacity(0.10),
                        size: 272
                    )

                    VStack(spacing: 6) {
                        Text(adhdVM.focusRemainingString)
                            .font(.system(size: timerSize * 1.15, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: adhdVM.focusRemainingString)
                            .accessibilityIdentifier("focus-timer-remaining")

                        Text(adhdVM.isPaused ? "PAUSED" : "REMAINING")
                            .font(.dsCaption(weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.45))
                            .accessibilityIdentifier("focus-timer-status")
                    }
                }
                .padding(.vertical, DesignSystem.spacingSM)

                // Elapsed time
                Text("Elapsed \(adhdVM.focusElapsedString)")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.4))

                // Hyperfocus warning
                if adhdVM.focusBreakReminder {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("You've been focused for a long time. Take a break?")
                    }
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                            .fill(Color.white.opacity(0.08))
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer(minLength: DesignSystem.spacingLG)

                // Primary control — a single, unmistakable pause/resume action.
                Button(action: {
                    HapticManager.impact(.medium)
                    if adhdVM.isPaused {
                        adhdVM.resumeFocusSession()
                    } else {
                        adhdVM.pauseFocusSession()
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: adhdVM.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(adhdVM.isPaused ? "RESUME" : "PAUSE")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .tracking(1.0)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Capsule().fill(DesignSystem.accentPrimary))
                }
                .padding(.horizontal, DesignSystem.spacingXL)
                .accessibilityIdentifier("focus-session-pause-toggle")

                // Secondary controls: adjust duration, skip break, end session.
                HStack(spacing: DesignSystem.spacingMD) {
                    Button(action: { adhdVM.reduceTime(minutes: 5) }) {
                        Text("-5 min")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }

                    Button(action: { showingDurationPicker = true }) {
                        Image(systemName: "timer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accent)
                            .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }

                    Button(action: { adhdVM.addTime(minutes: 5) }) {
                        Text("+5 min")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }

                    if adhdVM.isOnBreak {
                        Button(action: {
                            HapticManager.impact(.light)
                            adhdVM.skipBreak()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                    }
                }

                Button(action: {
                    HapticManager.notification(.warning)
                    adhdVM.endFocusSession()
                }) {
                    Text("End Session")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.bottom, DesignSystem.spacingLG)
                .accessibilityIdentifier("focus-session-stop")
            }
            .padding(.horizontal, DesignSystem.spacingMD)
        }
        .sheet(isPresented: $showingDurationPicker) {
            NavigationStack {
                PremiumForm {
                    Section("Focus Duration") {
                        Stepper("\(adhdVM.focusDurationMinutes) minutes", value: $adhdVM.focusDurationMinutes, in: 5...120, step: 5)
                    }
                    Section("Short Break") {
                        Stepper("\(adhdVM.breakDurationMinutes) minutes", value: $adhdVM.breakDurationMinutes, in: 1...30, step: 1)
                    }
                    Section("Long Break") {
                        Stepper("\(adhdVM.longBreakMinutes) minutes", value: $adhdVM.longBreakMinutes, in: 5...60, step: 5)
                    }
                    Section("Sessions Before Long Break") {
                        Stepper("\(adhdVM.sessionsBeforeLongBreak) sessions", value: $adhdVM.sessionsBeforeLongBreak, in: 2...8, step: 1)
                    }
                }
                .navigationTitle("Timer Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            adhdVM.saveTimerSettings()
                            showingDurationPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .accessibilityIdentifier("screen-focus-session")
    }

    @ViewBuilder
    private var focusBreatheGlow: some View {
        let glowColor = (adhdVM.isOnBreak ? DesignSystem.textSecondary : DesignSystem.accentPrimary)
            .opacity(0.22)
        if reduceMotion {
            Circle()
                .fill(glowColor)
                .frame(width: 300, height: 300)
                .blur(radius: 32)
        } else {
            PhaseAnimator([false, true]) { phase in
                Circle()
                    .fill(glowColor)
                    .frame(width: 300, height: 300)
                    .scaleEffect(phase ? 1.10 : 0.90)
                    .blur(radius: 32)
            } animation: { _ in
                .easeInOut(duration: 4)
            }
        }
    }
}

/// Body Doubling View — virtual co-working presence with ambient timer.
struct BodyDoublingView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var breatheAnimation = false
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingXL) {
                Spacer()
                
                // Breathing circle animation (static when Reduce Motion)
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        DesignSystem.accentGlow,
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: reduceMotion ? 110 : (breatheAnimation ? 150 : 80)
                                )
                            )
                            .frame(width: 300, height: 300)
                            .scaleEffect(reduceMotion ? 1.0 : (breatheAnimation ? 1.2 : 0.8))
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 4)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.5),
                                value: breatheAnimation
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 36))
                            .foregroundColor(DesignSystem.textMuted)
                        
                        Text("Body Doubling")
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("You're not alone. Keep going. 💙")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
                
                // Timer
                Text(adhdVM.bodyDoublingElapsedString)
                    .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                    .foregroundColor(DesignSystem.textPrimary)
                
                Text("Time working together")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                
                Spacer()
                
                // End button
                Button(action: { adhdVM.endBodyDoubling() }) {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(DesignSystem.contentSurfaceElevated)
                        )
                }
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            breatheAnimation = true
        }
    }
}

/// Task Initiation Countdown — 3-2-1 GO animation.
struct TaskInitiationView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: DesignSystem.spacingLG) {
                if let task = adhdVM.currentFocusTask {
                    Text(task.title)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Text("\(adhdVM.countdownValue)")
                    .font(.system(size: 120, weight: .heavy, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                    .scaleEffect(1.0)
                    .animation(.spring(response: 0.3), value: adhdVM.countdownValue)
                
                Text(adhdVM.countdownValue > 0 ? "Get ready..." : "GO!")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}
