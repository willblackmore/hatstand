import Foundation

struct ValidationIssue: Equatable, Hashable {
    enum Severity { case error, warning }
    enum Field { case name, appData, claudeCode, location }

    let severity: Severity
    let field: Field
    let message: String

    static func error(_ field: Field, _ message: String) -> ValidationIssue {
        ValidationIssue(severity: .error, field: field, message: message)
    }

    static func warning(_ field: Field, _ message: String) -> ValidationIssue {
        ValidationIssue(severity: .warning, field: field, message: message)
    }
}

extension Array where Element == ValidationIssue {
    var hasErrors: Bool { contains { $0.severity == .error } }
    func issues(for field: ValidationIssue.Field) -> [ValidationIssue] { filter { $0.field == field } }
}

/// Pure validation rules for instance names and folders.
/// Paths passed in must already be standardised.
struct InstanceValidator {
    let locations: ClaudeDefaultLocations

    init(locations: ClaudeDefaultLocations = ClaudeDefaultLocations()) {
        self.locations = locations
    }

    // MARK: Names

    /// - Parameters:
    ///   - existing: every instance, including the default one.
    ///   - excluding: the instance being renamed, if any.
    func validateName(_ name: String, existing: [Instance], excluding: UUID? = nil) -> ValidationIssue? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .error(.name, "Enter a name.")
        }
        let clash = existing.contains {
            $0.id != excluding
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(trimmed, options: [.caseInsensitive]) == .orderedSame
        }
        if clash {
            return .error(.name, "An instance called “\(trimmed)” already exists.")
        }
        return nil
    }

    /// Characters that can't be used in a folder name created from the instance name.
    func folderNameIssue(_ name: String) -> ValidationIssue? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") || trimmed.contains(":") || trimmed.hasPrefix(".") {
            return .error(.name, "Names used for new folders can’t contain “/” or “:”, or start with “.”.")
        }
        return nil
    }

    // MARK: Paths

    /// Validates a pair of instance folders.
    /// - Parameters:
    ///   - existing: other custom instances (the default instance is ignored).
    ///   - excluding: the instance being edited, if any.
    func validatePaths(
        appData: String,
        claudeCode: String,
        existing: [Instance],
        excluding: UUID? = nil
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        for (field, path) in [(ValidationIssue.Field.appData, appData), (.claudeCode, claudeCode)] {
            if path.isEmpty {
                issues.append(.error(field, "Choose a folder."))
                continue
            }
            if let issue = defaultLocationIssue(path, field: field) {
                issues.append(issue)
            }
            if let other = existing.first(where: { other in
                other.id != excluding && !other.isDefault
                    && (PathComparison.overlaps(path, other.appDataPath)
                        || PathComparison.overlaps(path, other.claudeCodePath))
            }) {
                issues.append(.error(field, "This folder overlaps with “\(other.name)”. Each instance needs its own folders."))
            }
            if isInICloudSyncedFolder(path) {
                issues.append(.warning(field, "This folder may be synced to iCloud, which can cause problems for Claude’s data. A folder in your Library is safer."))
            }
        }

        if !appData.isEmpty, !claudeCode.isEmpty, PathComparison.overlaps(appData, claudeCode) {
            issues.append(.error(.claudeCode, "The Claude Code folder must be separate from the app data folder."))
        }

        return issues
    }

    /// Paths may not be one of Claude's default locations, inside one, or
    /// contain one (which would make the instance share the default's data).
    func defaultLocationIssue(_ path: String, field: ValidationIssue.Field) -> ValidationIssue? {
        let home = PathStandardiser.standardise(locations.homeDirectory, homeDirectory: locations.homeDirectory)
        if PathComparison.isSame(path, home) || PathComparison.isEqualOrInside(home, path) {
            return .error(field, "Choose a more specific folder, not your home folder or a folder that contains it.")
        }
        for location in locations.all {
            if PathComparison.isEqualOrInside(path, location) {
                return .error(field, "This is one of Claude’s default locations, which belong to the default instance.")
            }
            if PathComparison.isEqualOrInside(location, path) {
                return .error(field, "This folder contains one of Claude’s default locations, which belong to the default instance.")
            }
        }
        return nil
    }

    func isInICloudSyncedFolder(_ path: String) -> Bool {
        locations.iCloudSyncedFolders.contains { PathComparison.isEqualOrInside(path, $0) }
    }
}
