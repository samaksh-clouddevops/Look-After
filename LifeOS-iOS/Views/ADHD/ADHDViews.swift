import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSData
import LifeOSFeatures

/// Emergency Mode — shows only top 3 tasks with large tap targets, minimal UI.
/// Designed for overwhelm moments when the user needs maximum simplicity.
struct EmergencyModeView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    let onStartTask: (LifeTask) -> Void
    
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
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusLG)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

/// Focus Session View — timer with progress ring, pause/resume, breaks, and duration controls.
struct FocusSessionView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    @State private var showingDurationPicker = false
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingLG) {
                Spacer()
                
                // Session state label
                HStack(spacing: 8) {
                    Circle()
                        .fill(adhdVM.isOnBreak ? DesignSystem.textSecondary : DesignSystem.accentPrimary)
                        .frame(width: 8, height: 8)
                    Text(adhdVM.sessionLabel.uppercased())
                        .font(.dsMetadata(weight: .bold))
                        .foregroundColor(adhdVM.isOnBreak ? DesignSystem.textSecondary : DesignSystem.accentPrimary)
                    Text("•")
                        .foregroundColor(DesignSystem.textMuted)
                    Text(adhdVM.sessionCounterString)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // Task name
                if let task = adhdVM.currentFocusTask {
                    Text(task.title)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Timer ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                        .frame(width: 220, height: 220)
                    
                    Circle()
                        .trim(from: 0, to: adhdVM.focusProgress)
                        .stroke(
                            adhdVM.isOnBreak ? DesignSystem.textSecondary : DesignSystem.accentPrimary,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: adhdVM.focusProgress)
                    
                    VStack(spacing: 4) {
                        Text(adhdVM.focusRemainingString)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text(adhdVM.isPaused ? "paused" : "remaining")
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                
                // Elapsed time
                Text("Elapsed: \(adhdVM.focusElapsedString)")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
                
                // +/- time controls
                HStack(spacing: 16) {
                    Button(action: { adhdVM.reduceTime(minutes: 5) }) {
                        Text("-5 min")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    
                    Button(action: { showingDurationPicker = true }) {
                        Image(systemName: "timer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.accentPrimary)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    
                    Button(action: { adhdVM.addTime(minutes: 5) }) {
                        Text("+5 min")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                
                // Hyperfocus warning
                if adhdVM.focusBreakReminder {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("You've been focused for a long time. Take a break?")
                    }
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .padding()
                    .elevatedSurface(cornerRadius: DesignSystem.radiusMD)
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Main controls
                HStack(spacing: DesignSystem.spacingXL) {
                    // Pause / Resume
                    Button(action: {
                        HapticManager.impact(.medium)
                        if adhdVM.isPaused {
                            adhdVM.resumeFocusSession()
                        } else {
                            adhdVM.pauseFocusSession()
                        }
                    }) {
                        Image(systemName: adhdVM.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                            )
                    }

                    if adhdVM.isOnBreak {
                        Button(action: {
                            HapticManager.impact(.light)
                            adhdVM.skipBreak()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.textMuted)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }

                    Button(action: {
                        HapticManager.notification(.warning)
                        adhdVM.endFocusSession()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.textMuted)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
                
                Spacer()
            }
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
    }
}

/// Body Doubling View — virtual co-working presence with ambient timer.
struct BodyDoublingView: View {
    
    @ObservedObject var adhdVM: ADHDViewModel
    
    @State private var breatheAnimation = false
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: DesignSystem.spacingXL) {
                Spacer()
                
                // Breathing circle animation
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
                                    endRadius: breatheAnimation ? 150 : 80
                                )
                            )
                            .frame(width: 300, height: 300)
                            .scaleEffect(breatheAnimation ? 1.2 : 0.8)
                            .animation(
                                .easeInOut(duration: 4)
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
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .onAppear {
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
