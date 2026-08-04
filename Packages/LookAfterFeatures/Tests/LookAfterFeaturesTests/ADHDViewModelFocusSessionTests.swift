import XCTest
@testable import LookAfterFeatures
import LookAfterCore

/// Focus session activation must be synchronous — UI overlays depend on instant state flips.
final class ADHDViewModelFocusSessionTests: XCTestCase {

    /// One frame at 60fps — focus state should flip before any async timer work.
    private let oneFrameMs: Double = 16
    private let activationHardFailMs: Double = 50

    @MainActor
    func testStartFocusSessionActivatesWithinOneFrame() throws {
        let vm = ADHDViewModel()
        let task = LifeTask(
            title: "Deep work",
            lifeArea: .work,
            estimatedMinutes: 45,
            userId: "test-user"
        )

        let start = CFAbsoluteTimeGetCurrent()
        vm.startFocusSession(task: task)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertTrue(vm.isFocusSessionActive, "Focus session should be active immediately")
        XCTAssertEqual(vm.currentFocusTask?.id, task.id)
        XCTAssertEqual(vm.focusSessionTarget, 45 * 60, accuracy: 0.1)
        XCTAssertLessThan(
            elapsedMs,
            activationHardFailMs,
            "Focus activation took \(elapsedMs)ms — target ≤ \(oneFrameMs)ms (hard fail > \(activationHardFailMs)ms)"
        )
    }

    @MainActor
    func testFocusDurationUsesScheduledWindowForLongWorkBlock() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let start = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day)!
        let end = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day)!

        let office = LifeTask(
            title: "Office",
            lifeArea: .work,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .fixedTime,
            scheduledEndTime: end,
            userId: "test-user"
        )

        let duration = ADHDViewModel.focusDuration(for: office, defaultMinutes: 25)
        XCTAssertEqual(duration, 540, "9h scheduled block should drive a 540-minute focus session")
    }

    @MainActor
    func testFocusDurationFallsBackToEstimateWhenNoScheduleWindow() {
        let task = LifeTask(
            title: "Review notes",
            lifeArea: .work,
            estimatedMinutes: 45,
            userId: "test-user"
        )

        let duration = ADHDViewModel.focusDuration(for: task, defaultMinutes: 25)
        XCTAssertEqual(duration, 45)
    }

    @MainActor
    func testPauseFocusSessionWithinOneFrame() throws {
        let vm = ADHDViewModel()
        let task = LifeTask(title: "Deep work", lifeArea: .work, estimatedMinutes: 25, userId: "test-user")
        vm.startFocusSession(task: task)

        let start = CFAbsoluteTimeGetCurrent()
        vm.pauseFocusSession()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertTrue(vm.isPaused)
        XCTAssertTrue(vm.isFocusSessionActive, "Session stays open while paused")
        XCTAssertLessThan(elapsedMs, activationHardFailMs, "Pause took \(elapsedMs)ms")
    }

    @MainActor
    func testResumeFocusSessionWithinOneFrame() throws {
        let vm = ADHDViewModel()
        let task = LifeTask(title: "Deep work", lifeArea: .work, estimatedMinutes: 25, userId: "test-user")
        vm.startFocusSession(task: task)
        vm.pauseFocusSession()

        let start = CFAbsoluteTimeGetCurrent()
        vm.resumeFocusSession()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertFalse(vm.isPaused)
        XCTAssertTrue(vm.isFocusSessionActive)
        XCTAssertLessThan(elapsedMs, activationHardFailMs, "Resume took \(elapsedMs)ms")
    }

    @MainActor
    func testEndFocusSessionWithinOneFrame() throws {
        let vm = ADHDViewModel()
        let task = LifeTask(title: "Deep work", lifeArea: .work, estimatedMinutes: 25, userId: "test-user")
        vm.startFocusSession(task: task)

        let start = CFAbsoluteTimeGetCurrent()
        vm.endFocusSession()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertFalse(vm.isFocusSessionActive)
        XCTAssertNil(vm.currentFocusTask)
        XCTAssertLessThan(elapsedMs, activationHardFailMs, "Stop took \(elapsedMs)ms")
    }
}
