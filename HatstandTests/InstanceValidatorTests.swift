import Testing
import Foundation
@testable import Hatstand

struct InstanceValidatorTests {
    // A home folder that doesn't exist, so standardising never touches real data.
    let home = "/Users/tester-that-does-not-exist"
    var locations: ClaudeDefaultLocations { ClaudeDefaultLocations(homeDirectory: home) }
    var validator: InstanceValidator { InstanceValidator(locations: locations) }

    func instance(_ name: String, _ appData: String, _ claudeCode: String) -> Instance {
        Instance(id: UUID(), name: name, appDataPath: home + appData, claudeCodePath: home + claudeCode)
    }

    func errors(appData: String, claudeCode: String, existing: [Instance] = []) -> [ValidationIssue] {
        validator.validatePaths(appData: home + appData, claudeCode: home + claudeCode, existing: existing)
            .filter { $0.severity == .error }
    }

    // MARK: Names

    @Test func rejectsEmptyName() {
        #expect(validator.validateName("   ", existing: []) != nil)
    }

    @Test func rejectsDuplicateNamesIgnoringCaseAndSpaces() {
        let existing = [Instance.makeDefault(name: "Work", locations: locations),
                        instance("Personal", "/p/app-data", "/p/claude-code")]
        #expect(validator.validateName("work", existing: existing) != nil)
        #expect(validator.validateName(" Personal ", existing: existing) != nil)
        #expect(validator.validateName("Another one", existing: existing) == nil)
    }

    @Test func allowsKeepingOwnNameWhenRenaming() {
        let personal = instance("Personal", "/p/app-data", "/p/claude-code")
        #expect(validator.validateName("personal", existing: [personal], excluding: personal.id) == nil)
    }

    @Test func rejectsFolderUnfriendlyNames() {
        #expect(validator.folderNameIssue("a/b") != nil)
        #expect(validator.folderNameIssue("a:b") != nil)
        #expect(validator.folderNameIssue(".hidden") != nil)
        #expect(validator.folderNameIssue("Personal") == nil)
    }

    // MARK: Paths

    @Test func acceptsSeparateFolders() {
        #expect(errors(appData: "/.claude-instances/personal", claudeCode: "/.claude-personal").isEmpty)
    }

    @Test func rejectsDefaultLocationsAndInsideThem() {
        #expect(!errors(appData: "/Library/Application Support/Claude", claudeCode: "/x").isEmpty)
        #expect(!errors(appData: "/Library/Application Support/Claude/sub", claudeCode: "/x").isEmpty)
        #expect(!errors(appData: "/a", claudeCode: "/.claude").isEmpty)
        #expect(!errors(appData: "/a", claudeCode: "/.claude/projects").isEmpty)
        #expect(!errors(appData: "/a", claudeCode: "/.claude.json").isEmpty)
    }

    @Test func doesNotConfuseSimilarNames() {
        // ~/.claude-personal is not inside ~/.claude.
        #expect(errors(appData: "/a", claudeCode: "/.claude-personal").isEmpty)
        #expect(errors(appData: "/Library/Application Support/Claude Personal", claudeCode: "/b").isEmpty)
    }

    @Test func rejectsFoldersContainingDefaultLocations() {
        #expect(!errors(appData: "/Library/Application Support", claudeCode: "/x").isEmpty)
        #expect(!validator.validatePaths(appData: home, claudeCode: home + "/x", existing: []).filter { $0.severity == .error }.isEmpty)
        #expect(!validator.validatePaths(appData: "/Users", claudeCode: home + "/x", existing: []).filter { $0.severity == .error }.isEmpty)
    }

    @Test func rejectsEmptyPaths() {
        let issues = validator.validatePaths(appData: "", claudeCode: "", existing: [])
        #expect(issues.issues(for: .appData).contains { $0.severity == .error })
        #expect(issues.issues(for: .claudeCode).contains { $0.severity == .error })
    }

    @Test func rejectsSharedOrNestedPathsBetweenInstances() {
        let personal = instance("Personal", "/p/app-data", "/p/claude-code")
        #expect(!errors(appData: "/p/app-data", claudeCode: "/q/claude-code", existing: [personal]).isEmpty)
        #expect(!errors(appData: "/q/app-data", claudeCode: "/p/claude-code", existing: [personal]).isEmpty)
        #expect(!errors(appData: "/p/app-data/nested", claudeCode: "/q/claude-code", existing: [personal]).isEmpty)
        #expect(!errors(appData: "/p", claudeCode: "/q/claude-code", existing: [personal]).isEmpty)
        // Swapped round: one instance's app data used as another's Claude Code folder.
        #expect(!errors(appData: "/q/app-data", claudeCode: "/p/app-data", existing: [personal]).isEmpty)
        #expect(errors(appData: "/q/app-data", claudeCode: "/q/claude-code", existing: [personal]).isEmpty)
    }

    @Test func ignoresTheInstanceBeingEdited() {
        let personal = instance("Personal", "/p/app-data", "/p/claude-code")
        let issues = validator.validatePaths(appData: personal.appDataPath, claudeCode: personal.claudeCodePath,
                                             existing: [personal], excluding: personal.id)
        #expect(!issues.hasErrors)
    }

    @Test func rejectsAppDataAndClaudeCodeOverlapping() {
        #expect(!errors(appData: "/p", claudeCode: "/p").isEmpty)
        #expect(!errors(appData: "/p", claudeCode: "/p/claude-code").isEmpty)
    }

    @Test func warnsButDoesNotBlockForICloudFolders() {
        let issues = validator.validatePaths(appData: home + "/Documents/Claude/app-data",
                                             claudeCode: home + "/Desktop/claude-code", existing: [])
        #expect(!issues.hasErrors)
        #expect(issues.filter { $0.severity == .warning }.count == 2)

        let driveIssues = validator.validatePaths(appData: home + "/Library/Mobile Documents/com~apple~CloudDocs/a",
                                                  claudeCode: home + "/b", existing: [])
        #expect(driveIssues.contains { $0.severity == .warning && $0.field == .appData })
    }

    @Test func suggestedParentIsValidAndNotInICloud() {
        let base = locations.suggestedInstancesParent + "/Personal"
        let issues = validator.validatePaths(appData: base + "/app-data", claudeCode: base + "/claude-code", existing: [])
        #expect(issues.isEmpty)
    }
}
