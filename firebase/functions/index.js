/**
 * Look After — proactive push sender (Phase 2).
 *
 * Mirrors client NotificationPolicyEngine rules:
 * - Max 2 proactive notifications per user per day
 * - Priority: medication > meeting prep > task due > morning briefing > brain hero
 * - Focus break is session-local only (never sent from server)
 *
 * Deploy: firebase deploy --only functions:sendProactiveNudges
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

const MAX_PROACTIVE_PER_DAY = 2;

const PRIORITY = {
  medication: 1,
  meetingPrep: 2,
  taskDue: 3,
  morningBriefing: 4,
  brainHero: 5,
};

function dayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function rankCandidate(candidate) {
  return PRIORITY[candidate.kind] ?? 99;
}

exports.sendProactiveNudges = onSchedule("every 15 minutes", async () => {
  const db = admin.firestore();
  const today = dayKey();
  const usersSnap = await db.collection("users").limit(200).get();

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const pendingRef = userDoc.ref.collection("notificationState").doc("pending");
    const pendingSnap = await pendingRef.get();
    if (!pendingSnap.exists) continue;

    const data = pendingSnap.data() || {};
    const budgetDay = data.budgetDay || today;
    let deliveredCount = data.deliveredCount || 0;
    if (budgetDay !== today) {
      deliveredCount = 0;
    }

    const candidates = (data.candidates || [])
      .filter((c) => c.kind !== "focusBreak")
      .sort((a, b) => rankCandidate(a) - rankCandidate(b) || a.fireAt - b.fireAt);

    const remaining = Math.max(0, MAX_PROACTIVE_PER_DAY - deliveredCount);
    const toSend = candidates.slice(0, remaining);
    if (toSend.length === 0) continue;

    const devicesSnap = await userDoc.ref.collection("devices").limit(10).get();
    const tokens = devicesSnap.docs.map((d) => d.id).filter(Boolean);
    if (tokens.length === 0) continue;

    for (const candidate of toSend) {
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: candidate.title || "Look After",
          body: candidate.body || "",
        },
        data: {
          kind: candidate.kind,
          route: candidate.route,
          routePayload: candidate.routePayload || "",
          candidateID: candidate.id,
        },
        apns: {
          payload: {
            aps: {
              category: "lookafter.proactive",
            },
          },
        },
      });
    }

    await pendingRef.set(
      {
        budgetDay: today,
        deliveredCount: deliveredCount + toSend.length,
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
});
