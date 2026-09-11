import XCTest
import LookAfterCore

final class GLMConfigurationTests: XCTestCase {

    func testModelsToAttempt_fallsBackFromGLM53ToFlash() {
        let config = GLMConfiguration(
            defaultModel: "glm-5.3",
            standardModel: "glm-5.3",
            economyModel: "glm-5.3-flash"
        )

        XCTAssertEqual(config.modelsToAttempt(primary: "glm-5.3"), ["glm-5.3", "glm-5.3-flash"])
    }

    func testModelsToAttempt_doesNotFallbackFlashToItself() {
        let config = GLMConfiguration.default
        XCTAssertEqual(config.modelsToAttempt(primary: "glm-5.3-flash"), ["glm-5.3-flash"])
    }

    func testFallbackTiers_premiumIncludesEconomy() {
        let config = GLMConfiguration.default
        XCTAssertEqual(config.fallbackTiers(startingAt: .premium), [.premium, .economy])
        XCTAssertEqual(config.fallbackTiers(startingAt: .standard), [.standard, .economy])
        XCTAssertEqual(config.model(for: .premium), "glm-5.3")
        XCTAssertEqual(config.model(for: .standard), "glm-5.3")
        XCTAssertEqual(config.model(for: .economy), "glm-5.3-flash")
    }

    func testUsesFlashFallback_detectsGLM5Family() {
        XCTAssertTrue(GLMConfiguration.usesFlashFallback("glm-5.3"))
        XCTAssertTrue(GLMConfiguration.usesFlashFallback("glm-5.2"))
        XCTAssertTrue(GLMConfiguration.usesFlashFallback("glm-4.7"))
        XCTAssertFalse(GLMConfiguration.usesFlashFallback("glm-5.3-flash"))
        XCTAssertFalse(GLMConfiguration.usesFlashFallback("glm-4.7-flash"))
        XCTAssertFalse(GLMConfiguration.usesFlashFallback("glm-4.7-flashx"))
    }

    func testDefaultModels() {
        XCTAssertEqual(GLMConfiguration.defaultModel, "glm-5.3")
        XCTAssertEqual(GLMConfiguration.defaultStandardModel, "glm-5.3")
        XCTAssertEqual(GLMConfiguration.defaultEconomyModel, "glm-5.3-flash")
        XCTAssertEqual(GLMConfiguration.flashFallbackModel, "glm-5.3-flash")
    }

    func testRequiresMandatoryThinking_forGLM53AndLater() {
        XCTAssertTrue(GLMConfiguration.requiresMandatoryThinking("glm-5.3"))
        XCTAssertTrue(GLMConfiguration.requiresMandatoryThinking("glm-5.3-flash"))
        XCTAssertTrue(GLMConfiguration.requiresMandatoryThinking("GLM-5.4"))
        XCTAssertFalse(GLMConfiguration.requiresMandatoryThinking("glm-5.2"))
        XCTAssertFalse(GLMConfiguration.requiresMandatoryThinking("glm-4.7"))
    }

    func testMigrateLegacyModels() {
        var config = GLMConfiguration(
            defaultModel: "glm-5.2",
            standardModel: "glm-4.7",
            economyModel: "glm-4.7-flash"
        )
        XCTAssertTrue(config.migrateLegacyModelsIfNeeded())
        XCTAssertEqual(config.defaultModel, "glm-5.3")
        XCTAssertEqual(config.standardModel, "glm-5.3")
        XCTAssertEqual(config.economyModel, "glm-5.3-flash")
        XCTAssertFalse(config.migrateLegacyModelsIfNeeded())
    }
}
