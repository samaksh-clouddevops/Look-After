import Foundation

/// Preferred TTS backend.
public enum SpeechVoiceProvider: String, CaseIterable, Identifiable, Sendable {
    case appleEnhanced = "apple_enhanced"
    case appleStandard = "apple_standard"
    /// Reserved for future cloud TTS (ElevenLabs / OpenAI / etc.).
    case cloud = "cloud"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleEnhanced: return "Apple Enhanced"
        case .appleStandard: return "Apple Standard"
        case .cloud: return "Cloud (coming soon)"
        }
    }

    public var detail: String {
        switch self {
        case .appleEnhanced: return "Best on-device neural voices when downloaded."
        case .appleStandard: return "System default English voice."
        case .cloud: return "Higher-fidelity voices when a provider is configured."
        }
    }
}

/// Preference keys + loaders for executive spoken voice.
public enum SpeechVoiceSettings {
    public static let providerKey = "lookafter.speech.provider"
    public static let voiceIdentifierKey = "lookafter.speech.voiceIdentifier"
    public static let rateKey = "lookafter.speech.rate"
    public static let pitchKey = "lookafter.speech.pitch"
    public static let autoSpeakRepliesKey = "lookafter.speech.autoSpeakReplies"
    public static let spokenStyleKey = "lookafter.speech.spokenStyle"

    /// 0.0 … 1.0 relative to default AVSpeech rate band (mapped in synthesizer).
    public static var rate: Double {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: rateKey) == nil { return 0.48 }
            return defaults.double(forKey: rateKey)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0.35), 0.65), forKey: rateKey) }
    }

    /// 0.5 … 2.0 (AVSpeechUtterance pitch range).
    public static var pitch: Double {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: pitchKey) == nil { return 1.0 }
            return defaults.double(forKey: pitchKey)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0.75), 1.25), forKey: pitchKey) }
    }

    public static var provider: SpeechVoiceProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: providerKey) ?? SpeechVoiceProvider.appleEnhanced.rawValue
            return SpeechVoiceProvider(rawValue: raw) ?? .appleEnhanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    public static var voiceIdentifier: String? {
        get {
            let value = UserDefaults.standard.string(forKey: voiceIdentifierKey)
            return (value?.isEmpty == false) ? value : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceIdentifierKey) }
    }

    public static var autoSpeakReplies: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: autoSpeakRepliesKey) == nil { return true }
            return defaults.bool(forKey: autoSpeakRepliesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoSpeakRepliesKey) }
    }

    /// When true, LLM coach/planning replies are instructed for spoken delivery.
    public static var preferSpokenStyle: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: spokenStyleKey) == nil { return true }
            return defaults.bool(forKey: spokenStyleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: spokenStyleKey) }
    }

    /// Block injected into system prompts when spoken style is preferred.
    public static var spokenDeliveryInstruction: String {
        """
        SPOKEN DELIVERY:
        - Your reply may be read aloud by a warm executive voice assistant.
        - Use short conversational sentences (1–3 for status updates, max ~6 for explanations).
        - No markdown, bullets, numbered lists, code, or tables.
        - No emojis. Expand abbreviations (say "minutes" not "min").
        - Sound calm, clear, and human — like a trusted chief of staff speaking in person.
        """
    }
}
