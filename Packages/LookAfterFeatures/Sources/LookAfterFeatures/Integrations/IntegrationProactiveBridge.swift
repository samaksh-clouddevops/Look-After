import Foundation
import LookAfterCore
import LookAfterIntegrations

/// Merges email triage and travel disruption into proactive actions.
public enum IntegrationProactiveBridge {
    public static func emailAndTravelActions(
        timelineEvents: [LifeTimelineEvent],
        now: Date = Date()
    ) async -> [ProactiveAction] {
        guard GmailOAuthService.isEnabled else {
            if let disruption = TravelDisruptionDetector.evaluate(timelineEvents: timelineEvents, now: now) {
                return [TravelDisruptionDetector.proactiveAction(from: disruption)]
            }
            return []
        }
        var actions: [ProactiveAction] = []
        do {
            let threads = try await GmailSyncService.shared.fetchUnreadThreads(limit: 10)
            let triaged = await EmailTriageClassifier.classify(threads: threads)
            await EmailTriageStore.shared.replaceAll(triaged)
            actions += EmailTriageClassifier.proactiveActions(from: triaged)
            let emailSubjects = triaged.map { (id: $0.thread.id, subject: $0.thread.subject, snippet: $0.thread.snippet) }
            if let disruption = TravelDisruptionDetector.evaluate(
                timelineEvents: timelineEvents,
                emailSubjects: emailSubjects,
                now: now
            ) {
                actions.append(TravelDisruptionDetector.proactiveAction(from: disruption))
            }
        } catch {
            print("[IntegrationProactiveBridge] \(error.localizedDescription)")
        }
        return actions
    }
}
