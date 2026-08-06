import XCTest
@testable import LookAfterCore

/// In-memory caches on UserLifeProfileStore / LifeModelStore / MedicationStore.
final class HotPathStoreCacheTests: XCTestCase {

    override func tearDown() {
        UserLifeProfileStore.reset()
        LifeModelStore.reset()
        MedicationStore.reset()
        super.tearDown()
    }

    func testUserLifeProfileStore_loadReturnsCachedValueAfterSave() {
        var profile = UserLifeProfile()
        profile.preferredName = "CacheProbe"
        profile.peakStartHour = 7
        UserLifeProfileStore.save(profile)

        // Corrupt defaults behind the cache — load must still serve memory.
        UserDefaults.standard.removeObject(forKey: UserLifeProfileStore.storageKey)

        let loaded = UserLifeProfileStore.load()
        XCTAssertEqual(loaded.preferredName, "CacheProbe")
        XCTAssertEqual(loaded.peakStartHour, 7)
    }

    func testUserLifeProfileStore_resetClearsCache() {
        var profile = UserLifeProfile()
        profile.preferredName = "Gone"
        UserLifeProfileStore.save(profile)
        UserLifeProfileStore.reset()

        XCTAssertTrue(UserLifeProfileStore.load().preferredName.isEmpty)
    }

    func testUserLifeProfileStore_invalidateCacheForcesReload() {
        var profile = UserLifeProfile()
        profile.preferredName = "Stale"
        UserLifeProfileStore.save(profile)

        UserDefaults.standard.removeObject(forKey: UserLifeProfileStore.storageKey)
        UserLifeProfileStore.invalidateCache()

        XCTAssertTrue(UserLifeProfileStore.load().preferredName.isEmpty)
    }

    func testLifeModelStore_loadReturnsCachedValueAfterSave() {
        let model = LifeModel(rawMarkdown: "# Cached model", identity: LifeIdentity(name: "Sam"))
        LifeModelStore.save(model)

        UserDefaults.standard.removeObject(forKey: LifeModelStore.storageKey)

        let loaded = LifeModelStore.load()
        XCTAssertEqual(loaded?.rawMarkdown, "# Cached model")
        XCTAssertEqual(loaded?.identity.name, "Sam")
        XCTAssertTrue(LifeModelStore.hasCompiledModel)
    }

    func testLifeModelStore_resetAndInvalidateClearCache() {
        LifeModelStore.save(LifeModel(rawMarkdown: "wipe me"))
        LifeModelStore.reset()
        XCTAssertNil(LifeModelStore.load())
        XCTAssertFalse(LifeModelStore.hasCompiledModel)

        LifeModelStore.save(LifeModel(rawMarkdown: "again"))
        UserDefaults.standard.removeObject(forKey: LifeModelStore.storageKey)
        LifeModelStore.invalidateCache()
        XCTAssertNil(LifeModelStore.load())
    }

    func testMedicationStore_loadReturnsCachedValueAfterSave() {
        let med = Medication(name: "Magnesium", dosage: "200mg", scheduledTime: Date())
        MedicationStore.save([med])

        UserDefaults.standard.removeObject(forKey: MedicationStore.userDefaultsKey)

        let loaded = MedicationStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Magnesium")
    }

    func testMedicationStore_resetAndInvalidateClearCache() {
        MedicationStore.save([
            Medication(name: "x", dosage: "1", scheduledTime: Date())
        ])
        MedicationStore.reset()
        XCTAssertTrue(MedicationStore.load().isEmpty)

        MedicationStore.save([
            Medication(name: "y", dosage: "1", scheduledTime: Date())
        ])
        UserDefaults.standard.removeObject(forKey: MedicationStore.userDefaultsKey)
        MedicationStore.invalidateCache()
        XCTAssertTrue(MedicationStore.load().isEmpty)
    }
}
