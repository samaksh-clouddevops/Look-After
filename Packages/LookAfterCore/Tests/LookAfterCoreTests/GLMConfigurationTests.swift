import XCTest
import LookAfterCore

final class GLMConfigurationTests: XCTestCase {

    func testModelsToAttempt_fallsBackFromGLM52ToFlash() {
        let config = GLMConfiguration(
            defaultModel: "glm-5.2",
            standardModel: "glm-4.7",
            economyModel: "glm-4.7-flash"
        )

        XCTAssertEqual(config.modelsToAttempt(primary: "glm-5.2"), ["glm-5.2", "glm-4.7-flash"])
        XCTAssertEqual(config.modelsToAttempt(primary: "glm-4.7"), ["glm-4.7", "glm-4.7-flash"])
    }

    func testModelsToAttempt_doesNotFallbackFlashToItself() {
        let config = GLMConfiguration.default
        XCTAssertEqual(config.modelsToAttempt(primary: "glm-4.7-flash"), ["glm-4.7-flash"])
    }

    func testFallbackTiers_premiumIncludesEconomy() {
        let config = GLMConfiguration.default
        XCTAssertEqual(config.fallbackTiers(startingAt: .premium), [.premium, .economy])
        XCTAssertEqual(config.fallbackTiers(startingAt: .standard), [.standard, .economy])
    }

    func testUsesFlashFallback_detectsGLM5Family() {
        XCTAssertTrue(GLMConfiguration.usesFlashFallback("glm-5.2"))
        XCTAssertTrue(GLMConfiguration.usesFlashFallback("glm-4.7"))
        XCTAssertFalse(GLMConfiguration.usesFlashFallback("glm-4.7-flash"))
        XCTAssertFalse(GLMConfiguration.usesFlashFallback("glm-4.7-flashx"))
    }
}
