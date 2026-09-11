import XCTest
@testable import LookAfterAI
import LookAfterCore

final class GLMUsageLoggerTests: XCTestCase {
    func testFreeFlashModelsCostZero() {
        let models = ["glm-4.7-flash", "GLM-4.7-Flash", "glm-4.5-flash", "glm-4.6v-flash"]
        for model in models {
            let cost = GLMUsageLogger.estimateCostUSD(model: model, promptTokens: 1_000_000, completionTokens: 1_000_000)
            XCTAssertEqual(cost, 0, accuracy: 0.000001, "Expected free pricing for \(model)")
        }
    }

    func testGLM53FlashIsPaid() {
        let cost = GLMUsageLogger.estimateCostUSD(model: "glm-5.3-flash", promptTokens: 1_000_000, completionTokens: 1_000_000)
        XCTAssertEqual(cost, 0.65, accuracy: 0.000001)
    }

    func testFlashXModelsArePaid() {
        let cost = GLMUsageLogger.estimateCostUSD(model: "glm-4.7-flashx", promptTokens: 1_000_000, completionTokens: 1_000_000)
        XCTAssertEqual(cost, 0.47, accuracy: 0.000001)
    }

    func testStandardGLM47IsPaid() {
        let cost = GLMUsageLogger.estimateCostUSD(model: "glm-4.7", promptTokens: 1_000_000, completionTokens: 1_000_000)
        XCTAssertEqual(cost, 2.8, accuracy: 0.000001)
    }

    func testPremiumGLM53IsPaid() {
        let cost = GLMUsageLogger.estimateCostUSD(model: "glm-5.3", promptTokens: 1_000_000, completionTokens: 1_000_000)
        XCTAssertEqual(cost, 5.8, accuracy: 0.000001)
    }
}
