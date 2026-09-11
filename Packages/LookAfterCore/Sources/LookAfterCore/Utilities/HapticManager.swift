import Foundation
#if os(iOS)
import UIKit
#endif

/// Tactile Dopamine Engine — triggers physical sensory haptic feedback for ADHD neurological reinforcement.
public struct HapticManager {
    
    public static func impact(_ style: ImpactStyle = .medium) {
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .medium:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        case .soft:
            generator = UIImpactFeedbackGenerator(style: .soft)
        case .rigid:
            generator = UIImpactFeedbackGenerator(style: .rigid)
        }
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    public static func notification(_ type: NotificationType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        switch type {
        case .success:
            generator.notificationOccurred(.success)
        case .warning:
            generator.notificationOccurred(.warning)
        case .error:
            generator.notificationOccurred(.error)
        }
        #endif
    }
    
    public enum ImpactStyle {
        case light, medium, heavy, soft, rigid
    }
    
    public enum NotificationType {
        case success, warning, error
    }
}
