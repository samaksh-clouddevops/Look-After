import Foundation

/// Localized chrome / shared UI copy (String Catalog in LookAfterCore).
/// `defaultValue` keeps English usable if the catalog table is missing in a given bundle (e.g. some SPM test hosts).
public enum LookAfterL10n {
    public static var tabBriefing: String {
        String(localized: "tab.briefing", defaultValue: "Briefing", bundle: .module)
    }

    public static var tabToday: String {
        String(localized: "tab.today", defaultValue: "Today", bundle: .module)
    }

    public static var tabReview: String {
        String(localized: "tab.review", defaultValue: "Review", bundle: .module)
    }

    public static var tabBrain: String {
        String(localized: "tab.brain", defaultValue: "Brain", bundle: .module)
    }

    public static var tabYou: String {
        String(localized: "tab.you", defaultValue: "You", bundle: .module)
    }

    public static var tabCapture: String {
        String(localized: "tab.capture", defaultValue: "Capture", bundle: .module)
    }

    public static var widgetNow: String {
        String(localized: "widget.now", defaultValue: "NOW", bundle: .module)
    }

    public static var widgetNextStep: String {
        String(localized: "widget.next_step", defaultValue: "Next step", bundle: .module)
    }

    public static var widgetAllClear: String {
        String(localized: "widget.all_clear", defaultValue: "All clear", bundle: .module)
    }

    public static var widgetNothingUrgent: String {
        String(localized: "widget.nothing_urgent", defaultValue: "Nothing urgent right now", bundle: .module)
    }

    public static var widgetStartFocus: String {
        String(localized: "widget.start_focus", defaultValue: "Start focus", bundle: .module)
    }

    public static var widgetEnergy: String {
        String(localized: "widget.energy", defaultValue: "ENERGY", bundle: .module)
    }

    public static var widgetTasks: String {
        String(localized: "widget.tasks", defaultValue: "TASKS", bundle: .module)
    }

    public static var widgetNoActiveTasks: String {
        String(localized: "widget.no_active_tasks", defaultValue: "No active tasks", bundle: .module)
    }

    public static var widgetMindClear: String {
        String(localized: "widget.mind_clear", defaultValue: "Your mind is clear", bundle: .module)
    }

    public static var widgetConfigNowName: String {
        String(localized: "widget.configuration.now.name", defaultValue: "Next Step", bundle: .module)
    }

    public static var widgetConfigNowDescription: String {
        String(
            localized: "widget.configuration.now.description",
            defaultValue: "See your top task and energy level at a glance.",
            bundle: .module
        )
    }

    public static func widgetDoneToday(count: Int) -> String {
        let format = String(
            localized: "widget.done_today.format",
            defaultValue: "%lld done today",
            bundle: .module
        )
        return String(format: format, locale: .current, count)
    }
}
