import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// Wires FlowDirector with production dependencies for the iOS app layer.
enum FlowDirectorFactory {

    @MainActor
    static func make(userName: String = "") async -> FlowDirector {
        let backend = FileBehaviorMemoryPersistenceBackend()
        let store = await BehaviorMemoryStore(backend: backend)
        let environment = EnvironmentContextProvider(
            calendarProvider: EventKitCalendarEnvironmentSignalProvider()
        )
        return FlowDirector(
            session: FlowDirectorSession(userName: userName),
            behaviorStore: store,
            analysisEngine: DefaultBehaviorAnalysisEngine(),
            environmentSource: environment
        )
    }
}
