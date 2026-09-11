import AppIntents
import LookAfterCore

/// Focus Filter App Intent — lets iOS bind Look After task context to a system Focus.
///
/// Users configure this once in Settings → Focus → [Mode] → Focus Filters → Look After.
/// When our filter is active for a Focus, iOS applies that Focus when we request the filter
/// representation; clearing the filter restores the previous Focus state.
struct LookAfterFocusIntent: SetFocusFilterIntent {

    static let title: LocalizedStringResource = "Look After Focus"
    static let description = IntentDescription(
        "Applies a Look After workspace while a focus block is active — deep work, recovery, health, or admin."
    )

    /// Category of the active LifeTask (Deep Work, Recovery, …).
    @Parameter(title: "Task Category", default: .deepWork)
    var activeTaskCategory: FocusFilterCategoryAppEnum

    /// Human-readable title of the active block.
    @Parameter(title: "Active Task")
    var activeTaskTitle: String?

    /// Whether low-priority notifications should be suppressed.
    @Parameter(title: "Suppress Low Priority", default: true)
    var suppressLowPriority: Bool

    /// Constraint surface (Anchored / Flexible / Recovery).
    @Parameter(title: "Constraint")
    var constraintLabel: String?

    var displayRepresentation: DisplayRepresentation {
        let category = activeTaskCategory.displayName
        if let title = activeTaskTitle, !title.isEmpty {
            return DisplayRepresentation(title: "\(category): \(title)")
        }
        return DisplayRepresentation(title: "\(category) Focus")
    }

    init() {}

    init(
        category: FocusTaskCategory,
        taskTitle: String?,
        suppressLowPriority: Bool,
        constraintLabel: String?
    ) {
        self.activeTaskCategory = FocusFilterCategoryAppEnum(category)
        self.activeTaskTitle = taskTitle
        self.suppressLowPriority = suppressLowPriority
        self.constraintLabel = constraintLabel
    }

    func perform() async throws -> some IntentResult {
        let category = activeTaskCategory.domain
        let title = activeTaskTitle
        let suppress = suppressLowPriority
        await MainActor.run {
            ExecutionFocusFilterStore.shared.record(
                category: category,
                taskTitle: title,
                suppressLowPriority: suppress
            )
        }
        return .result()
    }
}

// MARK: - AppEnum bridge

enum FocusFilterCategoryAppEnum: String, AppEnum {
    case deepWork
    case recovery
    case admin
    case health
    case creative
    case social
    case fluidGap

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Focus Category")

    static let caseDisplayRepresentations: [FocusFilterCategoryAppEnum: DisplayRepresentation] = [
        .deepWork: "Deep Work",
        .recovery: "Recovery",
        .admin: "Admin",
        .health: "Health",
        .creative: "Creative",
        .social: "Social",
        .fluidGap: "Fluid Gap"
    ]

    var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .recovery: return "Recovery"
        case .admin: return "Admin"
        case .health: return "Health"
        case .creative: return "Creative"
        case .social: return "Social"
        case .fluidGap: return "Fluid Gap"
        }
    }

    var domain: FocusTaskCategory {
        FocusTaskCategory(rawValue: rawValue) ?? .deepWork
    }

    init(_ category: FocusTaskCategory) {
        self = FocusFilterCategoryAppEnum(rawValue: category.rawValue) ?? .deepWork
    }
}

// MARK: - Lightweight filter store (app process)

/// Records the last Focus Filter the system asked us to apply.
@MainActor
final class ExecutionFocusFilterStore {
    static let shared = ExecutionFocusFilterStore()

    private(set) var activeCategory: FocusTaskCategory?
    private(set) var activeTaskTitle: String?
    private(set) var suppressLowPriority = false
    private(set) var updatedAt: Date?

    private init() {}

    func record(category: FocusTaskCategory, taskTitle: String?, suppressLowPriority: Bool) {
        activeCategory = category
        activeTaskTitle = taskTitle
        self.suppressLowPriority = suppressLowPriority
        updatedAt = Date()
    }

    func clear() {
        activeCategory = nil
        activeTaskTitle = nil
        suppressLowPriority = false
        updatedAt = Date()
    }
}
