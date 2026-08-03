import Foundation

public enum EVPPaths {
    public static func findRepoRoot(startingAt path: String = FileManager.default.currentDirectoryPath) -> String {
        var current = (path as NSString).standardizingPath
        let fm = FileManager.default
        while true {
            let qaPath = (current as NSString).appendingPathComponent("Documentation/qa")
            if fm.fileExists(atPath: qaPath) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return path
    }

    public static var repoRoot: String { findRepoRoot() }

    public static var qaRoot: String {
        (repoRoot as NSString).appendingPathComponent("Documentation/qa")
    }

    public static var engineOutput: String {
        (qaRoot as NSString).appendingPathComponent(".engine")
    }

    public static var fixturesRoot: String {
        (qaRoot as NSString).appendingPathComponent("fixtures")
    }

    public static func qaDoc(_ name: String) -> String {
        (qaRoot as NSString).appendingPathComponent(name)
    }

    public static func fixture(_ subpath: String) -> String {
        (fixturesRoot as NSString).appendingPathComponent(subpath)
    }

    public static func engineArtifact(_ name: String) -> String {
        (engineOutput as NSString).appendingPathComponent(name)
    }
}

public enum EVPConstants {
    public static let northStarQuestion =
        "If I shipped this Executive Brain today, would it make better decisions for a real person over the next 30 days than the previous version?"
}
