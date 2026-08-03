import XCTest
@testable import LifeOSCore

final class ExperienceModeTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ExperienceMode.storageKey)
        super.tearDown()
    }

    func testDefaultIsClassic() {
        XCTAssertEqual(ExperienceMode.current, .classic)
    }

    func testSaveAndLoadAIExecutive() {
        ExperienceMode.save(.aiExecutive)
        XCTAssertEqual(ExperienceMode.current, .aiExecutive)
        XCTAssertTrue(ExperienceMode.isAIExecutiveEnabled)
    }

    func testDisplayNames() {
        XCTAssertEqual(ExperienceMode.classic.displayName, "Classic")
        XCTAssertEqual(ExperienceMode.aiExecutive.displayName, "Companion")
    }
}
