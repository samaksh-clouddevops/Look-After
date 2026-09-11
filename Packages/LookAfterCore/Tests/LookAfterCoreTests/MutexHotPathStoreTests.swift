import Foundation
import Testing
@testable import LookAfterCore

/// Swift 6 isolation coverage for Mutex-backed hot-path stores.
/// Serialized because these types share `UserDefaults.standard`.
@Suite(.serialized)
struct MutexHotPathStoreTests {

    init() {
        MedicationStore.reset()
        UserLifeProfileStore.reset()
        LifeModelStore.reset()
        FreshInstallGuard.exit()
    }

    @Test func freshInstallGuardTogglesUnderMutex() {
        #expect(FreshInstallGuard.isActive == false)
        FreshInstallGuard.enter()
        #expect(FreshInstallGuard.isActive)
        FreshInstallGuard.exit()
        #expect(FreshInstallGuard.isActive == false)
    }

    @Test func medicationStoreCacheSurvivesConcurrentReads() async {
        let med = Medication(name: "MutexProbe", dosage: "10mg", scheduledTime: Date(timeIntervalSince1970: 1_800_000_000))
        MedicationStore.save([med])

        let names = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    MedicationStore.load().first?.name
                }
            }
            var collected: [String?] = []
            for await name in group {
                collected.append(name)
            }
            return collected
        }

        #expect(names.count == 24)
        #expect(names.allSatisfy { $0 == "MutexProbe" })
    }

    @Test func medicationStoreInvalidateCacheForcesReload() {
        let med = Medication(name: "StaleCache", dosage: "5mg", scheduledTime: Date(timeIntervalSince1970: 1_800_000_000))
        MedicationStore.save([med])
        UserDefaults.standard.removeObject(forKey: MedicationStore.userDefaultsKey)
        MedicationStore.invalidateCache()

        #expect(MedicationStore.load().isEmpty)
    }

    @Test func userLifeProfileStoreCacheServesAfterDefaultsWipe() {
        var profile = UserLifeProfile()
        profile.preferredName = "MutexName"
        profile.peakStartHour = 7
        UserLifeProfileStore.save(profile)
        UserDefaults.standard.removeObject(forKey: UserLifeProfileStore.storageKey)

        let loaded = UserLifeProfileStore.load()
        #expect(loaded.preferredName == "MutexName")
        #expect(loaded.peakStartHour == 7)
    }

    @Test func userLifeProfileStoreResetClearsCache() {
        var profile = UserLifeProfile()
        profile.preferredName = "Gone"
        UserLifeProfileStore.save(profile)
        UserLifeProfileStore.reset()

        #expect(UserLifeProfileStore.load().preferredName.isEmpty)
    }

    @Test func lifeModelStoreInvalidateCacheForcesReload() {
        #expect(LifeModelStore.load() == nil)
        LifeModelStore.invalidateCache()
        #expect(LifeModelStore.load() == nil)
        #expect(LifeModelStore.hasCompiledModel == false)
    }
}
