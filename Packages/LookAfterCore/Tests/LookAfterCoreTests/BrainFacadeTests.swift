import XCTest
@testable import LookAfterCore

final class BrainFacadeTests: XCTestCase {

    func testShortSleepPrefersRecovery() async {
        let facade = DeterministicBrainFacadeBackend()
        let out = await facade.recommend(
            BrainFacadeInput(userId: "u", sleepHours: 4.5, activeTaskCount: 3)
        )
        XCTAssertEqual(out?.backendID, "deterministic.recovery")
        XCTAssertTrue(out?.headline.lowercased().contains("capacity") == true
            || out?.headline.lowercased().contains("protect") == true)
    }

    func testEmptyBoardSuggestsCapture() async {
        let facade = DeterministicBrainFacadeBackend()
        let out = await facade.recommend(
            BrainFacadeInput(userId: "u", sleepHours: 8, activeTaskCount: 0)
        )
        XCTAssertEqual(out?.backendID, "deterministic.capture")
    }

    func testRouterFallsBack() async {
        struct Empty: BrainFacadeProtocol {
            func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput? { nil }
        }
        let router = BrainFacadeRouter(primary: Empty(), fallback: DeterministicBrainFacadeBackend())
        let out = await router.recommend(BrainFacadeInput(userId: "u", activeTaskCount: 2))
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.backendID, "deterministic.next")
    }
}
