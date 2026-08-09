import Foundation
import LookAfterCore

/// Short spoken opener when the Brain tab starts a voice session proactively.
public enum BrainVoiceWelcomeBuilder {

    public static func message(
        presentation: BrainPresentation,
        userName: String,
        hasPriorConversation: Bool = false
    ) -> String {
        if hasPriorConversation {
            return "I'm still here — pick up where we left off, or tell me what's changed."
        }

        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = presentation.greeting.trimmingCharacters(in: .whitespacesAndNewlines)
        let salutation: String
        if !greeting.isEmpty {
            if name.isEmpty || greeting.localizedCaseInsensitiveContains(name) {
                salutation = greeting.hasSuffix(".") ? greeting : "\(greeting)."
            } else {
                salutation = "\(greeting), \(name)."
            }
        } else if name.isEmpty {
            salutation = "Hey there."
        } else {
            salutation = "Hey \(name)."
        }

        if let heroTitle = presentation.hero?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !heroTitle.isEmpty {
            return "\(salutation) I see \(heroTitle) on your plan. What's on your mind?"
        }

        if let coach = presentation.coachMoment?.trimmingCharacters(in: .whitespacesAndNewlines),
           !coach.isEmpty {
            return "\(salutation) \(coach) What would help most right now?"
        }

        return "\(salutation) I'm here to help you think through your day. What would you like to talk about?"
    }
}
