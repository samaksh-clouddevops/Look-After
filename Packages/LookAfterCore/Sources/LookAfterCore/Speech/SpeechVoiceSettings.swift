import Foundation

/// Preferred TTS backend.
public enum SpeechVoiceProvider: String, CaseIterable, Identifiable, Sendable {
    case appleEnhanced = "apple_enhanced"
    case appleStandard = "apple_standard"
    /// OpenAI neural TTS (tts-1-hd) — proxied through the licensed auth API.
    case cloud = "cloud"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleEnhanced: return "Apple Enhanced"
        case .appleStandard: return "Apple Standard"
        case .cloud: return "Cloud (OpenAI)"
        }
    }

    public var detail: String {
        switch self {
        case .appleEnhanced: return "Best on-device neural voices when downloaded."
        case .appleStandard: return "System default English voice."
        case .cloud: return "Natural neural voice via licensed secure proxy."
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
    public static let autoSpeakProactiveKey = "lookafter.speech.autoSpeakProactive"
    public static let spokenStyleKey = "lookafter.speech.spokenStyle"
    public static let cloudVoiceKey = "lookafter.speech.cloudVoice"
    public static let licenseActiveKey = "lookafter.license.active"

    /// OpenAI TTS voices — warm, conversational options first.
    public static let cloudVoices: [(id: String, label: String)] = [
        ("nova", "Nova (warm, conversational)"),
        ("shimmer", "Shimmer (soft, friendly)"),
        ("alloy", "Alloy (neutral, clear)"),
        ("echo", "Echo (male, calm)"),
        ("fable", "Fable (expressive)"),
        ("onyx", "Onyx (deep, authoritative)"),
    ]

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

    public static var cloudVoice: String {
        get {
            let stored = UserDefaults.standard.string(forKey: cloudVoiceKey)
            if let stored, cloudVoices.contains(where: { $0.id == stored }) { return stored }
            return "nova"
        }
        set { UserDefaults.standard.set(newValue, forKey: cloudVoiceKey) }
    }

    public static var isCloudTTSAvailable: Bool {
        provider == .cloud && UserDefaults.standard.bool(forKey: licenseActiveKey)
    }

    public static var autoSpeakReplies: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: autoSpeakRepliesKey) == nil { return true }
            return defaults.bool(forKey: autoSpeakRepliesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoSpeakRepliesKey) }
    }

    public static var autoSpeakProactive: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: autoSpeakProactiveKey) == nil { return false }
            return defaults.bool(forKey: autoSpeakProactiveKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoSpeakProactiveKey) }
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

    /// Premium / enhanced voice identifiers to try before falling back to compact system voices.
    public static let preferredVoiceIdentifiers: [String] = [
        "com.apple.voice.premium.en-US.Zoe",
        "com.apple.voice.premium.en-US.Samantha",
        "com.apple.voice.premium.en-US.Ava",
        "com.apple.voice.enhanced.en-US.Samantha",
        "com.apple.voice.enhanced.en-US.Alex",
        "com.apple.voice.premium.en-GB.Daniel",
        "com.apple.voice.enhanced.en-GB.Daniel",
        "com.apple.voice.premium.en-AU.Karen",
        "com.apple.voice.enhanced.en-AU.Karen",
        "com.apple.voice.premium.en-IE.Moira",
        "com.apple.voice.enhanced.en-IE.Moira",
    ]
}
