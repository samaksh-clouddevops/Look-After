import Foundation

/// Seeds the Behavioral Vault from a mathematical `RhythmProfile`.
/// All seeded signatures use confidence 0.2 and overrideCount 0 so the first
/// user contradiction immediately rewrites the baseline (immediate capitulation).
public enum BehavioralVaultSeeder {

    /// Common semantic-hash stems used at Day-1 (stable tokens, not user-facing labels).
    public enum HashStem {
        public static let meetingStandup = "meeting|standup"
        public static let meetingGeneric = "meeting|meeting"
        public static let deepWork = "deepwork|deep_work"
        public static let adminEmail = "administrative|email"
        public static let errand = "errand|errands"
        public static let commute = "travel|commute"
        public static let workout = "physicalactivity|gym"
        public static let creative = "creative|creative_block"
    }

    /// Build seeded signatures from calendar rhythm. Does not merge into a vault.
    public static func signatures(
        from profile: RhythmProfile,
        now: Date = Date()
    ) -> [BehavioralSignature] {
        let meeting = profile.meetingBaselineConstraint
        let morning = profile.todBaselineConstraint[.morning] ?? .flexible
        let afternoon = profile.todBaselineConstraint[.afternoon] ?? .flexible
        let evening = profile.todBaselineConstraint[.evening] ?? .fluid

        // Seeded rows — always confidence 0.2 / override 0.
        return [
            .seededBaseline(hash: HashStem.meetingStandup, constraint: meeting, now: now),
            .seededBaseline(hash: HashStem.meetingGeneric, constraint: meeting, now: now),
            .seededBaseline(hash: HashStem.deepWork, constraint: morning, now: now),
            .seededBaseline(hash: HashStem.adminEmail, constraint: afternoon, now: now),
            .seededBaseline(hash: HashStem.errand, constraint: evening == .anchored ? .flexible : evening, now: now),
            .seededBaseline(hash: HashStem.commute, constraint: profile.typicalStartHour <= 10 ? .anchored : .flexible, now: now),
            .seededBaseline(hash: HashStem.workout, constraint: evening, now: now),
            .seededBaseline(hash: HashStem.creative, constraint: morning, now: now),
        ]
    }

    /// Seed vault only when empty. Returns whether seeding occurred.
    @discardableResult
    public static func seedIfEmpty(
        profile: RhythmProfile,
        envelope: inout BehavioralVaultEnvelope,
        now: Date = Date()
    ) -> Bool {
        guard envelope.signatures.isEmpty else { return false }
        for signature in signatures(from: profile, now: now) {
            // Enforce seeder contract explicitly.
            var s = signature
            s.confidence = .seededLow
            s.overrideCount = 0
            s.isSeededBaseline = true
            envelope.upsert(s, now: now)
        }
        return true
    }

    /// Analyze 6 months of calendar history and seed.
    /// Always runs poison filter (all-day / title spam). Pass `metaByID` for subscribed calendars.
    @discardableResult
    public static func seedFromCalendarHistory(
        events: [CalendarHistoryEvent],
        metaByID: [String: CalendarEventSourceMeta] = [:],
        envelope: inout BehavioralVaultEnvelope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (seeded: Bool, profile: RhythmProfile) {
        let clean = CalendarEventPoisonFilter.filter(events, metaByID: metaByID)
        let profile = CalendarRhythmAnalyzer.analyze(events: clean, now: now, calendar: calendar)
        let seeded = seedIfEmpty(profile: profile, envelope: &envelope, now: now)
        return (seeded, profile)
    }
}
