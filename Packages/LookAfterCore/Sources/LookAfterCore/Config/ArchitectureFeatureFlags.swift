import Foundation

/// Architecture / infra rollout flags (Phase 0 — MASTER-IMPLEMENTATION-PLAN).
///
/// Defaults are **off** (legacy path) until a phase soaks and defaults flip on.
/// Keys use the `lookafter.arch.*` prefix so they don't collide with product toggles.
public enum ArchitectureFeatureFlags {

    public enum Key {
        public static let useSessionContainer = "lookafter.arch.useSessionContainer"
        public static let useSyncOutbox = "lookafter.arch.useSyncOutbox"
        public static let proxyOnlyAI = "lookafter.arch.proxyOnlyAI"
        public static let useBrainFacade = "lookafter.arch.useBrainFacade"
        public static let useTypedEventBus = "lookafter.arch.useTypedEventBus"
    }

    private static var defaults: UserDefaults { .standard }

    /// When true, app builds dependencies via `SessionContainer` instead of ad hoc singletons.
    public static var useSessionContainer: Bool {
        get { bool(for: Key.useSessionContainer, default: false) }
        set { defaults.set(newValue, forKey: Key.useSessionContainer) }
    }

    /// When true, cloud mutations go through the SQLite sync outbox worker.
    public static var useSyncOutbox: Bool {
        get { bool(for: Key.useSyncOutbox, default: false) }
        set { defaults.set(newValue, forKey: Key.useSyncOutbox) }
    }

    /// When true, GLM must use auth-proxy (no on-device API key path).
    /// Release builds default **true** once the key is unset (safe default for App Store).
    public static var proxyOnlyAI: Bool {
        get {
            if defaults.object(forKey: Key.proxyOnlyAI) == nil {
                #if DEBUG
                return false
                #else
                return true
                #endif
            }
            return defaults.bool(forKey: Key.proxyOnlyAI)
        }
        set { defaults.set(newValue, forKey: Key.proxyOnlyAI) }
    }

    /// When true, `BrainViewModel` uses `BrainFacade` only.
    public static var useBrainFacade: Bool {
        get { bool(for: Key.useBrainFacade, default: false) }
        set { defaults.set(newValue, forKey: Key.useBrainFacade) }
    }

    /// When true, domain events publish on typed EventBus (may dual-publish Notifications).
    public static var useTypedEventBus: Bool {
        get { bool(for: Key.useTypedEventBus, default: false) }
        set { defaults.set(newValue, forKey: Key.useTypedEventBus) }
    }

    /// Snapshot for logging / Settings debug.
    public static var debugSnapshot: [String: Bool] {
        [
            "useSessionContainer": useSessionContainer,
            "useSyncOutbox": useSyncOutbox,
            "proxyOnlyAI": proxyOnlyAI,
            "useBrainFacade": useBrainFacade,
            "useTypedEventBus": useTypedEventBus,
        ]
    }

    /// Clears explicit overrides (restores compile-time defaults).
    public static func resetAllToDefaults() {
        [
            Key.useSessionContainer,
            Key.useSyncOutbox,
            Key.proxyOnlyAI,
            Key.useBrainFacade,
            Key.useTypedEventBus,
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    private static func bool(for key: String, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
