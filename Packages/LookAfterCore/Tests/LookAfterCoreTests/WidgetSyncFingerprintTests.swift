import Testing
import Foundation
@testable import LookAfterCore

struct WidgetSyncFingerprintTests {
    @Test
    func identicalSnapshotsSkipWriteUnlessForced() {
        let snapshot = WidgetSnapshot(topTaskTitle: "Focus", completedTodayCount: 1, activeTaskCount: 2)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fp = WidgetSyncFingerprint.compute(snapshot, now: now)
        #expect(WidgetSyncFingerprint.shouldWrite(force: false, fingerprint: fp, lastFingerprint: fp) == false)
        #expect(WidgetSyncFingerprint.shouldWrite(force: true, fingerprint: fp, lastFingerprint: fp) == true)
    }

    @Test
    func changedSnapshotWritesWithoutForce() {
        let a = WidgetSnapshot(topTaskTitle: "A", activeTaskCount: 1)
        let b = WidgetSnapshot(topTaskTitle: "B", activeTaskCount: 1)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fa = WidgetSyncFingerprint.compute(a, now: now)
        let fb = WidgetSyncFingerprint.compute(b, now: now)
        #expect(fa != fb)
        #expect(WidgetSyncFingerprint.shouldWrite(force: false, fingerprint: fb, lastFingerprint: fa) == true)
    }

    /// Regression: health-only changes (sleep/steps/HRV) must still restamp the widget even
    /// when tasks/energy are unchanged, otherwise EnergyWidget shows stale health metrics.
    @Test
    func healthOnlyChangeWritesWithoutForce() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = WidgetSnapshot(topTaskTitle: "Focus", activeTaskCount: 1, sleepHours: 6.5, stepCount: 1000, hrvMs: 40)
        let b = WidgetSnapshot(topTaskTitle: "Focus", activeTaskCount: 1, sleepHours: 6.5, stepCount: 5000, hrvMs: 40)
        let fa = WidgetSyncFingerprint.compute(a, now: now)
        let fb = WidgetSyncFingerprint.compute(b, now: now)
        #expect(fa != fb)
        #expect(WidgetSyncFingerprint.shouldWrite(force: false, fingerprint: fb, lastFingerprint: fa) == true)
    }
}
