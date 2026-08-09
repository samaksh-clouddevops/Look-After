import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// Physics-aware haptic feedback for timeline constraint gestures.
/// Prefers CHHapticEngine; falls back to UIImpactFeedbackGenerator when unavailable.
@MainActor
public final class InteractionEngine {
    public static let shared = InteractionEngine()

    #if os(iOS)
    private var engine: CHHapticEngine?
    private var engineAvailable = false
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    private init() {
        #if os(iOS)
        bootstrapEngine()
        #endif
    }

    /// Call at gesture start so the engine is warm before continuous pulses.
    public func prepare() {
        #if os(iOS)
        if engineAvailable {
            try? engine?.start()
        } else {
            lightImpact.prepare()
            mediumImpact.prepare()
            heavyImpact.prepare()
            softImpact.prepare()
            rigidImpact.prepare()
        }
        #endif
    }

    /// Continuous drag texture — intensity/sharpness scale with |velocity| (pts/s).
    public func dragTexture(velocity: Double, constraint: TimeConstraint) {
        #if os(iOS)
        let speed = min(1.0, abs(velocity) / 1800.0)
        let base: Double
        switch constraint {
        case .anchored: base = 0.55
        case .flexible: base = 0.28
        case .fluid: base = 0.12
        }
        let intensity = min(1.0, base + speed * 0.55)
        let sharpness: Double
        switch constraint {
        case .anchored: sharpness = 0.85
        case .flexible: sharpness = 0.45
        case .fluid: sharpness = 0.2
        }
        playTransient(intensity: intensity, sharpness: sharpness)
        #endif
    }

    /// Discrete threshold cross (constraint mutation).
    public func constraintChanged(to constraint: TimeConstraint) {
        #if os(iOS)
        switch constraint {
        case .anchored:
            playTransient(intensity: 1.0, sharpness: 1.0)
            heavyImpact.impactOccurred(intensity: 1.0)
        case .flexible:
            playTransient(intensity: 0.7, sharpness: 0.55)
            mediumImpact.impactOccurred(intensity: 0.85)
        case .fluid:
            playTransient(intensity: 0.4, sharpness: 0.25)
            softImpact.impactOccurred(intensity: 0.7)
        }
        #else
        _ = constraint
        #endif
    }

    /// Subtle tick when a drag crosses a schedule snap boundary (e.g. 15-minute grid).
    public func scheduleSnapBoundary() {
        #if os(iOS)
        playTransient(intensity: 0.35, sharpness: 0.3)
        lightImpact.impactOccurred(intensity: 0.45)
        #endif
    }

    /// Rubber-band edge tick for anchored blocks.
    public func rubberBandEdge() {
        #if os(iOS)
        playTransient(intensity: 0.65, sharpness: 0.9)
        rigidImpact.impactOccurred(intensity: 0.8)
        #endif
    }

    // MARK: - Private

    #if os(iOS)
    private func bootstrapEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engineAvailable = false
            return
        }
        do {
            let hapticEngine = try CHHapticEngine()
            hapticEngine.isAutoShutdownEnabled = true
            hapticEngine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.restartEngine()
                }
            }
            hapticEngine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.engineAvailable = false
                }
            }
            try hapticEngine.start()
            engine = hapticEngine
            engineAvailable = true
        } catch {
            engineAvailable = false
            engine = nil
        }
    }

    private func restartEngine() {
        guard let engine else {
            bootstrapEngine()
            return
        }
        do {
            try engine.start()
            engineAvailable = true
        } catch {
            engineAvailable = false
        }
    }

    private func playTransient(intensity: Double, sharpness: Double) {
        guard engineAvailable, let engine else {
            let style: HapticManager.ImpactStyle = intensity > 0.75 ? .heavy : (intensity > 0.4 ? .medium : .light)
            HapticManager.impact(style)
            return
        }
        let clampedI = max(0, min(1, intensity))
        let clampedS = max(0, min(1, sharpness))
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(clampedI))
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(clampedS))
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Low Power Mode / engine loss — fall back quietly.
            engineAvailable = false
            HapticManager.impact(intensity > 0.6 ? .medium : .light)
        }
    }
    #endif
}
