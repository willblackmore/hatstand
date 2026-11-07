import Foundation

/// Pure helpers for turning user-supplied paths into a single canonical form,
/// so that paths can be saved and compared reliably.
enum PathStandardiser {

    /// Returns an absolute, canonical version of `path`:
    /// - surrounding whitespace removed
    /// - `~` expanded using `homeDirectory`
    /// - `.` and `..` components and duplicate or trailing slashes removed
    /// - symbolic links resolved for every part of the path that exists on disk
    ///
    /// Relative paths are treated as relative to `homeDirectory`.
    static func standardise(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var expanded = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else { return "" }

        if expanded == "~" {
            expanded = homeDirectory
        } else if expanded.hasPrefix("~/") {
            expanded = homeDirectory + String(expanded.dropFirst(1))
        } else if !expanded.hasPrefix("/") {
            expanded = homeDirectory + "/" + expanded
        }

        let lexical = normaliseComponents(expanded)
        return resolvingSymlinks(lexical)
    }

    /// Collapses `.`/`..` and redundant slashes without touching the file system.
    static func normaliseComponents(_ absolutePath: String) -> String {
        var stack: [Substring] = []
        for component in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !stack.isEmpty { stack.removeLast() }
            default: stack.append(component)
            }
        }
        return "/" + stack.joined(separator: "/")
    }

    /// Resolves symbolic links in the longest prefix of `path` that exists, then
    /// re-appends the part that doesn't exist yet. Folders for new instances
    /// usually don't exist when they are first validated.
    private static func resolvingSymlinks(_ path: String) -> String {
        var existing = path
        var missing: [String] = []

        while existing != "/" {
            if let real = realPath(existing) {
                return join(real, missing.reversed())
            }
            let ns = existing as NSString
            missing.append(ns.lastPathComponent)
            existing = ns.deletingLastPathComponent
            if existing.isEmpty { existing = "/" }
        }
        return join(realPath("/") ?? "/", missing.reversed())
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func join(_ base: String, _ rest: [String]) -> String {
        guard !rest.isEmpty else { return base }
        let prefix = base == "/" ? "" : base
        return prefix + "/" + rest.joined(separator: "/")
    }
}

/// Comparisons between already-standardised paths. macOS volumes are
/// case-insensitive by default, so comparisons ignore case.
enum PathComparison {

    static func isSame(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive]) == .orderedSame
    }

    /// True if `path` is `container` or lies anywhere inside it.
    static func isEqualOrInside(_ path: String, _ container: String) -> Bool {
        let p = components(path)
        let c = components(container)
        guard p.count >= c.count else { return false }
        return zip(p, c).allSatisfy { isSame(String($0), String($1)) }
    }

    /// True if either path is equal to, or inside, the other.
    static func overlaps(_ a: String, _ b: String) -> Bool {
        isEqualOrInside(a, b) || isEqualOrInside(b, a)
    }

    private static func components(_ path: String) -> [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: true)
    }
}

/// Claude's normal data locations, used by the default instance.
struct ClaudeDefaultLocations {
    let homeDirectory: String

    init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    /// Electron app data (sign-in, chats, settings, MCP config, Cowork VM files).
    var appData: String { homeDirectory + "/Library/Application Support/Claude" }
    /// Claude Code data folder.
    var claudeCode: String { homeDirectory + "/.claude" }
    /// Claude Code's global config file, which lives beside its folder by default.
    var claudeCodeConfigFile: String { homeDirectory + "/.claude.json" }

    /// Every default location, standardised.
    var all: [String] {
        [appData, claudeCode, claudeCodeConfigFile].map {
            PathStandardiser.standardise($0, homeDirectory: homeDirectory)
        }
    }

    /// Folders that may be synced to iCloud.
    var iCloudSyncedFolders: [String] {
        [
            homeDirectory + "/Desktop",
            homeDirectory + "/Documents",
            homeDirectory + "/Library/Mobile Documents",
        ].map { PathStandardiser.standardise($0, homeDirectory: homeDirectory) }
    }

    /// Suggested parent folder for new instances (not iCloud-synced).
    var suggestedInstancesParent: String {
        homeDirectory + "/Library/Application Support/Hatstand/Instances"
    }
}

extension String {
    /// Replaces the home directory prefix with `~` for display.
    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
