import XCTest
@testable import LookAfterFeatures
import LookAfterAI
import LookAfterData

@MainActor
final class AppCompositionTests: XCTestCase {
    func testLiveCompositionBuildsCoreViewModels() {
        let composition = AppComposition.live
        let tasks = composition.makeTasksViewModel(decomposer: TaskDecomposer(glmService: GLMService.shared))
        let inbox = composition.makeInboxViewModel()
        XCTAssertNotNil(tasks)
        XCTAssertNotNil(inbox)
        XCTAssertTrue(composition.taskStore === TaskStore.shared)
    }
}
