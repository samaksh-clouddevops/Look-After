import Foundation
import Testing
import LookAfterCore
@testable import LookAfterAI

struct DecideForMeReliabilityTests {
    private let today = Calendar.current.startOfDay(for: Date())

    @Test func futureTasksAreNotSuggested() async {
        var task = LifeTask(title: "Tomorrow only")
        task.scheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: today)
        let picker = DecideForMePicker(glmService: MockGLM.service(stubbedResponse: "{}"))
        let result = await picker.pick(snapshot: CognitiveSnapshot(), tasks: [task], referenceDate: today)
        #expect(result == nil)
    }

    @Test func exactIDsDisambiguateIdenticalTitles() async throws {
        var first = LifeTask(title: "Read")
        first.scheduledDate = today
        var second = LifeTask(title: "Read")
        second.scheduledDate = today
        let glm = MockGLM.service(stubbedResponse: """
        {"selectedTaskID":"\(second.id)","reason":"A short reading break."}
        """)
        let result = try #require(await DecideForMePicker(glmService: glm).pick(
            snapshot: CognitiveSnapshot(), tasks: [first, second], referenceDate: today
        ))
        #expect(result.task.id == second.id)
        #expect(result.reason == "A short reading break.")
    }

    @Test(arguments: [
        "{\"selectedTaskID\":\"invented\",\"reason\":\"Untrusted explanation\"}",
        "{\"selectedTaskTitle\":\"Read\",\"reason\":\"Untrusted explanation\"}",
        "not JSON"
    ])
    func invalidSelectionsUseLocalFallback(response: String) async throws {
        var task = LifeTask(title: "Read a chapter")
        task.scheduledDate = today
        let picker = DecideForMePicker(glmService: MockGLM.service(stubbedResponse: response))
        let result = try #require(await picker.pick(
            snapshot: CognitiveSnapshot(), tasks: [task], referenceDate: today
        ))
        #expect(result.task.id == task.id)
        #expect(result.reason != "Untrusted explanation")
    }

    @Test func emptyDayReturnsNoSuggestion() async {
        let picker = DecideForMePicker(glmService: MockGLM.service(stubbedResponse: "{}"))
        #expect(await picker.pick(snapshot: CognitiveSnapshot(), tasks: []) == nil)
    }
}
