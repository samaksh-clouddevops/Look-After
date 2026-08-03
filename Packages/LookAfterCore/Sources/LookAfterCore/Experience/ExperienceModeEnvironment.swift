import SwiftUI

private struct ExperienceModeKey: EnvironmentKey {
    static let defaultValue: ExperienceMode = .current
}

public extension EnvironmentValues {
    var experienceMode: ExperienceMode {
        get { self[ExperienceModeKey.self] }
        set { self[ExperienceModeKey.self] = newValue }
    }
}
