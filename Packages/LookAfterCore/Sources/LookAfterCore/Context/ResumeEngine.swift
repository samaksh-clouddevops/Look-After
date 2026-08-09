import Foundation

/// Persists cross-session resume state so Home can restore the last working context.
public final class ResumeEngine: @unchecked Sendable {
    public static let shared = ResumeEngine()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func storageKey(userId: String) -> String {
        "lifeos.resume.\(userId.isEmpty ? "local" : userId)"
    }

    public func load(userId: String) -> ResumeSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: storageKey(userId: userId)),
              let snapshot = try? SharedFormatters.jsonDecoderSeconds.decode(ResumeSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.isStale ? nil : snapshot
    }

    public func save(_ snapshot: ResumeSnapshot, userId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(userId: userId))
    }

    public func clear(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey(userId: userId))
    }

    // MARK: - Capture helpers

    public func captureScreen(_ screen: String, userId: String, experienceMode: ExperienceMode? = nil) {
        mutate(userId: userId) { resume in
            resume.lastScreen = screen
            resume.experienceMode = experienceMode
            resume.savedAt = Date()
        }
    }

    public func captureTask(_ task: LifeTask, screen: String, userId: String) {
        mutate(userId: userId) { resume in
            resume.lastScreen = screen
            resume.lastTaskID = task.id
            resume.lastTaskTitle = task.title
            resume.workingContext = WorkingContext(kind: .task, title: task.title, taskID: task.id)
            resume.savedAt = Date()
        }
    }

    public func captureFocusSession(task: LifeTask, elapsedSeconds: Int, userId: String) {
        mutate(userId: userId) { resume in
            resume.lastScreen = "focus"
            resume.lastTimerTaskID = task.id
            resume.lastTimerTaskTitle = task.title
            resume.lastTimerElapsedSeconds = elapsedSeconds
            resume.lastTaskID = task.id
            resume.lastTaskTitle = task.title
            resume.workingContext = WorkingContext(
                kind: .focusSession,
                title: task.title,
                subtitle: "\(elapsedSeconds / 60)m in",
                taskID: task.id
            )
            resume.savedAt = Date()
        }
    }

    public func captureNote(_ text: String, userId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(userId: userId) { resume in
            resume.lastNote = trimmed
            resume.workingContext = WorkingContext(kind: .note, title: trimmed)
            resume.savedAt = Date()
        }
    }

    public func captureDocument(_ name: String, userId: String) {
        mutate(userId: userId) { resume in
            resume.lastDocument = name
            resume.workingContext = WorkingContext(kind: .document, title: name)
            resume.savedAt = Date()
        }
    }

    public func captureFile(_ path: String, userId: String) {
        mutate(userId: userId) { resume in
            resume.lastFile = path
            resume.workingContext = WorkingContext(kind: .file, title: path)
            resume.savedAt = Date()
        }
    }

    public func captureBrowserLink(_ url: String, userId: String) {
        mutate(userId: userId) { resume in
            resume.lastBrowserLink = url
            resume.workingContext = WorkingContext(kind: .browser, title: url)
            resume.savedAt = Date()
        }
    }

    public func captureAIConversation(_ preview: String, userId: String) {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(userId: userId) { resume in
            resume.lastAIConversationPreview = String(trimmed.prefix(200))
            resume.workingContext = WorkingContext(kind: .aiCoach, title: String(trimmed.prefix(80)))
            resume.savedAt = Date()
        }
    }

    /// Stores a privacy-safe blurred snapshot for hero/backdrop rendering.
    public func capturePreviewImage(_ data: Data, userId: String) {
        mutate(userId: userId) { resume in
            resume.previewImageData = data
            resume.savedAt = Date()
        }
    }

    private func mutate(userId: String, _ body: (inout ResumeSnapshot) -> Void) {
        var snapshot = load(userId: userId) ?? ResumeSnapshot()
        body(&snapshot)
        save(snapshot, userId: userId)
    }
}
