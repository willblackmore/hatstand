import Testing
import Foundation
@testable import Hatstand

/// A temporary folder that is removed when the test finishes.
final class TemporaryFolder {
    let path: String

    init() throws {
        let base = PathStandardiser.standardise(NSTemporaryDirectory())
        path = base + "/HatstandTests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func makeFolder(_ relative: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}

struct PathStandardiserTests {
    let home = "/Users/tester-that-does-not-exist"

    @Test func expandsTilde() {
        #expect(PathStandardiser.standardise("~", homeDirectory: home) == home)
        #expect(PathStandardiser.standardise("~/.claude-personal", homeDirectory: home) == home + "/.claude-personal")
    }

    @Test func treatsRelativePathsAsRelativeToHome() {
        #expect(PathStandardiser.standardise("Instances/Work", homeDirectory: home) == home + "/Instances/Work")
    }

    @Test func removesTrailingAndDuplicateSlashes() {
        #expect(PathStandardiser.standardise("~/a//b///", homeDirectory: home) == home + "/a/b")
    }

    @Test func collapsesDotComponents() {
        #expect(PathStandardiser.standardise("~/a/./b/../c", homeDirectory: home) == home + "/a/c")
        #expect(PathStandardiser.normaliseComponents("/../..") == "/")
    }

    @Test func trimsWhitespace() {
        #expect(PathStandardiser.standardise("  ~/a  \n", homeDirectory: home) == home + "/a")
        #expect(PathStandardiser.standardise("   ", homeDirectory: home) == "")
    }

    @Test func resolvesSymlinksInExistingParts() throws {
        let temp = try TemporaryFolder()
        let real = try temp.makeFolder("real")
        let link = temp.path + "/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        #expect(PathStandardiser.standardise(link) == real)
        // The part after the link doesn't exist yet but is kept.
        #expect(PathStandardiser.standardise(link + "/new/folder/") == real + "/new/folder")
    }

    @Test func isIdempotent() throws {
        let temp = try TemporaryFolder()
        let once = PathStandardiser.standardise(temp.path + "/x/../y/")
        #expect(PathStandardiser.standardise(once) == once)
    }
}

struct PathComparisonTests {
    @Test func equalOrInside() {
        #expect(PathComparison.isEqualOrInside("/a/b", "/a/b"))
        #expect(PathComparison.isEqualOrInside("/a/b/c", "/a/b"))
        #expect(!PathComparison.isEqualOrInside("/a/bc", "/a/b"))
        #expect(!PathComparison.isEqualOrInside("/a", "/a/b"))
        #expect(PathComparison.isEqualOrInside("/anything", "/"))
    }

    @Test func ignoresCase() {
        #expect(PathComparison.isSame("/Users/A/Folder", "/users/a/folder"))
        #expect(PathComparison.isEqualOrInside("/Users/A/Folder/x", "/users/a/folder"))
    }

    @Test func overlaps() {
        #expect(PathComparison.overlaps("/a", "/a/b"))
        #expect(PathComparison.overlaps("/a/b", "/a"))
        #expect(!PathComparison.overlaps("/a/b", "/a/c"))
    }
}
