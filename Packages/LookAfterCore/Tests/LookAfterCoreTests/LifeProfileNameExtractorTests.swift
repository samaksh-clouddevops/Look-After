import XCTest
@testable import LookAfterCore

final class LifeProfileNameExtractorTests: XCTestCase {

    func testExtractsFromImIntroduction() {
        let name = LifeProfileNameExtractor.extract(from: "I'm Alex, a product manager with ADHD.")
        XCTAssertEqual(name, "Alex")
    }

    func testExtractsFromMyNameIs() {
        let name = LifeProfileNameExtractor.extract(from: "My name is Alex and I work remotely.")
        XCTAssertEqual(name, "Alex")
    }

    func testExtractsFromStructuredPersonalitySection() {
        var sections = StructuredLifeProfileSections()
        sections.personality = "Call me Alex. I'm direct and async-first."

        let name = LifeProfileNameExtractor.extract(
            profileText: "",
            sections: sections
        )
        XCTAssertEqual(name, "Alex")
    }

    func testRejectsGenericIAmPhrase() {
        let name = LifeProfileNameExtractor.extract(from: "I am a PM with many meetings during the day.")
        XCTAssertNil(name)
    }

    func testResolvedDisplayNamePrefersSettingsOverride() {
        UserDefaults.standard.set("Manual Name", forKey: "userName")
        defer { UserDefaults.standard.removeObject(forKey: "userName") }

        var profile = UserLifeProfile()
        profile.profileText = "I'm Alex, a PM."
        profile.preferredName = "Alex"
        UserLifeProfileStore.save(profile)

        XCTAssertEqual(UserLifeProfileStore.resolvedDisplayName(), "Manual Name")
    }

    func testSyncUserNameFromProfileWhenSettingsEmpty() {
        UserDefaults.standard.removeObject(forKey: "userName")
        defer { UserDefaults.standard.removeObject(forKey: "userName") }

        var profile = UserLifeProfile()
        profile.profileText = "I'm Alex, a PM."
        UserLifeProfileStore.save(profile)

        XCTAssertEqual(UserDefaults.standard.string(forKey: "userName"), "Alex")
        XCTAssertEqual(UserLifeProfileStore.resolvedDisplayName(), "Alex")
    }
}
