package com.lookafter.core.modules

import kotlinx.serialization.Serializable

/** Availability of a feature module on Android. */
@Serializable
enum class ModuleStatus {
    SHIPPED,
    BETA,
    COMING_SOON,
    ;

    val label: String
        get() = when (this) {
            SHIPPED -> "Open"
            BETA -> "Beta"
            COMING_SOON -> "Soon"
        }
}

/** Destination keys consumed by the Android shell (not Compose-specific). */
@Serializable
enum class ModuleDestination {
    TODAY,
    BRIEFING,
    BRAIN,
    HEALTH,
    MEDICATION,
    INSIGHTS,
    INBOX,
    COMPANION,
    REVIEW,
    SIMULATION,
    NOTIFICATIONS,
    PRIVACY,
    TRAVEL,
    CYCLE,
    LEARNING,
    CREATIVITY,
    BEHAVIOR,
    LIFE_HUB,
    TOUR,
}

@Serializable
enum class ModuleGroup {
    DAILY,
    CARE,
    FOCUS,
    GROWTH,
    SYSTEM,
    ;

    val title: String
        get() = when (this) {
            DAILY -> "Daily"
            CARE -> "Care"
            FOCUS -> "Focus"
            GROWTH -> "Growth"
            SYSTEM -> "System"
        }
}

@Serializable
data class AppModule(
    val id: String,
    val title: String,
    val subtitle: String,
    val group: ModuleGroup,
    val destination: ModuleDestination,
    val status: ModuleStatus = ModuleStatus.SHIPPED,
    val sortOrder: Int = 0,
) {
    val isOpenable: Boolean
        get() = status == ModuleStatus.SHIPPED || status == ModuleStatus.BETA
}

/**
 * Pure module catalog — iOS Modules grid parity (Phase E0).
 * UI maps [ModuleDestination] to navigation; coming-soon modules stay unopenable.
 */
object AppModuleCatalog {

    val all: List<AppModule> = listOf(
        AppModule("today", "Today", "Board, filters, week strip", ModuleGroup.DAILY, ModuleDestination.TODAY, ModuleStatus.SHIPPED, 10),
        AppModule("briefing", "Briefing", "Morning narrative & capacity", ModuleGroup.DAILY, ModuleDestination.BRIEFING, ModuleStatus.SHIPPED, 20),
        AppModule("brain", "Brain", "Hero, coach, multi-day plans", ModuleGroup.DAILY, ModuleDestination.BRAIN, ModuleStatus.SHIPPED, 30),
        AppModule("inbox", "Inbox", "Capture & triage", ModuleGroup.DAILY, ModuleDestination.INBOX, ModuleStatus.SHIPPED, 40),
        AppModule("insights", "Insights", "Performance & tag heat", ModuleGroup.DAILY, ModuleDestination.INSIGHTS, ModuleStatus.SHIPPED, 50),
        AppModule("review", "Weekly review", "Reflect & reset", ModuleGroup.DAILY, ModuleDestination.REVIEW, ModuleStatus.SHIPPED, 60),

        AppModule("health", "Health", "Readiness & 7-day charts", ModuleGroup.CARE, ModuleDestination.HEALTH, ModuleStatus.SHIPPED, 110),
        AppModule("meds", "Medication", "Doses & adherence", ModuleGroup.CARE, ModuleDestination.MEDICATION, ModuleStatus.SHIPPED, 120),
        AppModule("cycle", "Cycle", "Capacity-aware cycle support", ModuleGroup.CARE, ModuleDestination.CYCLE, ModuleStatus.COMING_SOON, 130),

        AppModule("companion", "Body double", "WebRTC focus room", ModuleGroup.FOCUS, ModuleDestination.COMPANION, ModuleStatus.BETA, 210),
        AppModule("simulation", "Simulation", "What-if planning sandbox", ModuleGroup.FOCUS, ModuleDestination.SIMULATION, ModuleStatus.SHIPPED, 220),

        AppModule("travel", "Travel", "Trips, packing & day open", ModuleGroup.GROWTH, ModuleDestination.TRAVEL, ModuleStatus.SHIPPED, 310),
        AppModule("learning", "Learning", "Spaced practice loops", ModuleGroup.GROWTH, ModuleDestination.LEARNING, ModuleStatus.COMING_SOON, 320),
        AppModule("creativity", "Creativity", "Capture boards", ModuleGroup.GROWTH, ModuleDestination.CREATIVITY, ModuleStatus.COMING_SOON, 330),
        AppModule("behavior", "Behavior", "Habit loops", ModuleGroup.GROWTH, ModuleDestination.BEHAVIOR, ModuleStatus.COMING_SOON, 340),
        AppModule("life", "Life hub", "Goals & areas", ModuleGroup.GROWTH, ModuleDestination.LIFE_HUB, ModuleStatus.COMING_SOON, 350),
        AppModule("tour", "Tour", "Product coach marks", ModuleGroup.GROWTH, ModuleDestination.TOUR, ModuleStatus.COMING_SOON, 360),

        AppModule("notifications", "Notifications", "Quiet hours & pings", ModuleGroup.SYSTEM, ModuleDestination.NOTIFICATIONS, ModuleStatus.SHIPPED, 410),
        AppModule("privacy", "Privacy & data", "Export, reset, sign-in", ModuleGroup.SYSTEM, ModuleDestination.PRIVACY, ModuleStatus.SHIPPED, 420),
    ).sortedBy { it.sortOrder }

    fun byId(id: String): AppModule? = all.firstOrNull { it.id == id }

    fun openable(): List<AppModule> = all.filter { it.isOpenable }

    fun comingSoon(): List<AppModule> = all.filter { it.status == ModuleStatus.COMING_SOON }

    fun grouped(): List<Pair<ModuleGroup, List<AppModule>>> =
        ModuleGroup.entries.mapNotNull { g ->
            val items = all.filter { it.group == g }
            if (items.isEmpty()) null else g to items
        }

    fun search(query: String): List<AppModule> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return all
        return all.filter {
            it.title.lowercase().contains(q) ||
                it.subtitle.lowercase().contains(q) ||
                it.id.contains(q)
        }
    }
}
