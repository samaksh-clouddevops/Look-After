import Foundation
import LookAfterCore

public struct ProactiveActionBundle: Codable, Sendable, Equatable {
    public var mutations: [PlanMutation]
    public var variant: PlanVariant?
    public var focusSessionTaskID: String?
    public var focusSessionMinutes: Int?
    public var moduleRoute: String?

    public init(
        mutations: [PlanMutation] = [],
        variant: PlanVariant? = nil,
        focusSessionTaskID: String? = nil,
        focusSessionMinutes: Int? = nil,
        moduleRoute: String? = nil
    ) {
        self.mutations = mutations
        self.variant = variant
        self.focusSessionTaskID = focusSessionTaskID
        self.focusSessionMinutes = focusSessionMinutes
        self.moduleRoute = moduleRoute
    }
}

public enum ProactiveBundleMetadataKeys {
    public static let payload = "proactiveBundle"
    public static let variantID = "variantID"
}

public enum ProactiveActionBundleCodec {
    public static func encode(_ bundle: ProactiveActionBundle, into metadata: inout [String: String]) {
        if let data = try? JSONEncoder().encode(bundle),
           let json = String(data: data, encoding: .utf8) {
            metadata[ProactiveBundleMetadataKeys.payload] = json
        }
        if let variant = bundle.variant {
            metadata[ProactiveBundleMetadataKeys.variantID] = variant.id
        }
    }

    public static func decode(from action: ProactiveAction) -> ProactiveActionBundle? {
        guard let json = action.metadata[ProactiveBundleMetadataKeys.payload],
              let data = json.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(ProactiveActionBundle.self, from: data) else {
            return nil
        }
        return bundle
    }

    public static func action(_ action: ProactiveAction, attaching bundle: ProactiveActionBundle) -> ProactiveAction {
        var metadata = action.metadata
        encode(bundle, into: &metadata)
        return ProactiveAction(
            id: action.id,
            kind: action.kind,
            severity: action.severity,
            message: action.message,
            options: action.options,
            surface: action.surface,
            relatedTaskIDs: action.relatedTaskIDs,
            relatedInboxIDs: action.relatedInboxIDs,
            expiresAt: action.expiresAt,
            metadata: metadata
        )
    }
}
