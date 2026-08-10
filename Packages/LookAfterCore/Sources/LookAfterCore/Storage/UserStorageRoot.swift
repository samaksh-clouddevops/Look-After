import Foundation

/// Per-user document namespace (Phase 7.4).
///
/// Layout: `Documents/users/{sanitizedUid}/…`
/// Shared (non-user) data stays at Documents root until fully migrated.
public enum UserStorageRoot {

    private static let usersFolder = "users"

    /// Sanitized directory component for a uid (Firebase UIDs are already safe; guests need scrubbing).
    public static func sanitize(_ userId: String) -> String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "_anonymous" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scaled = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scaled.prefix(128))
    }

    public static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// `Documents/users/{uid}` — created if missing.
    @discardableResult
    public static func ensureUserDirectory(userId: String) -> URL {
        let root = documentsDirectory()
            .appendingPathComponent(usersFolder, isDirectory: true)
            .appendingPathComponent(sanitize(userId), isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public static func fileURL(userId: String, name: String) -> URL {
        ensureUserDirectory(userId: userId).appendingPathComponent(name, isDirectory: false)
    }

    /// List known user folders (debug / multi-account UI).
    public static func listedUserIds() -> [String] {
        let root = documentsDirectory().appendingPathComponent(usersFolder, isDirectory: true)
        guard let kids = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return kids.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
    }
}
