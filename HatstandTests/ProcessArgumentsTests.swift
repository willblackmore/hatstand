import Testing
import Foundation
@testable import Hatstand

struct ProcessArgumentParserTests {

    /// Builds a buffer in the `KERN_PROCARGS2` layout.
    func procArgs2(executable: String, arguments: [String], environment: [String], padding: Int = 3) -> [UInt8] {
        var argc = Int32(arguments.count)
        var bytes = withUnsafeBytes(of: &argc) { Array($0) }
        bytes += Array(executable.utf8) + [0]
        bytes += [UInt8](repeating: 0, count: padding)
        for arg in arguments { bytes += Array(arg.utf8) + [0] }
        for entry in environment { bytes += Array(entry.utf8) + [0] }
        // Apple-specific strings follow after an empty one; they must be ignored.
        bytes += [0] + Array("executable_file=0x1".utf8) + [0]
        return bytes
    }

    @Test func parsesProcArgs2() throws {
        let buffer = procArgs2(
            executable: "/Applications/Claude.app/Contents/MacOS/Claude",
            arguments: ["/Applications/Claude.app/Contents/MacOS/Claude",
                        "--user-data-dir=/Users/me/Library/Application Support/Hatstand/Instances/Personal/app-data"],
            environment: ["HOME=/Users/me", "CLAUDE_CONFIG_DIR=/Users/me/x y", "EMPTY="]
        )
        let info = try #require(ProcessArgumentParser.parseProcArgs2(buffer))
        #expect(info.executablePath == "/Applications/Claude.app/Contents/MacOS/Claude")
        #expect(info.arguments.count == 2)
        #expect(info.arguments[1].hasSuffix("Personal/app-data"))
        #expect(info.environment?["CLAUDE_CONFIG_DIR"] == "/Users/me/x y")
        #expect(info.environment?["EMPTY"] == "")
        #expect(info.environment?["executable_file"] == nil)
    }

    @Test func reportsUnreadableEnvironmentAsNil() throws {
        let buffer = procArgs2(executable: "/bin/x", arguments: ["/bin/x", "-a"], environment: [])
        let info = try #require(ProcessArgumentParser.parseProcArgs2(buffer))
        #expect(info.arguments == ["/bin/x", "-a"])
        #expect(info.environment == nil)
    }

    @Test func rejectsTruncatedBuffers() {
        #expect(ProcessArgumentParser.parseProcArgs2([]) == nil)
        #expect(ProcessArgumentParser.parseProcArgs2([1, 0]) == nil)
        // Says there are two arguments but only has one.
        var buffer = procArgs2(executable: "/bin/x", arguments: ["/bin/x"], environment: [], padding: 0)
        buffer[0] = 5
        buffer.removeLast(buffer.count - 4 - 7 - 7)
        #expect(ProcessArgumentParser.parseProcArgs2(buffer) == nil)
    }

    @Test func findsUserDataDirWithEquals() {
        let args = ["/Claude", "--foo", "--user-data-dir=/a b/c", "--bar"]
        #expect(ProcessArgumentParser.userDataDir(fromArguments: args) == "/a b/c")
    }

    @Test func findsUserDataDirAsSeparateArgument() {
        #expect(ProcessArgumentParser.userDataDir(fromArguments: ["/Claude", "--user-data-dir", "/a"]) == "/a")
    }

    @Test func lastUserDataDirWins() {
        let args = ["/Claude", "--user-data-dir=/first", "--user-data-dir=/second"]
        #expect(ProcessArgumentParser.userDataDir(fromArguments: args) == "/second")
    }

    @Test func noUserDataDirMeansNil() {
        #expect(ProcessArgumentParser.userDataDir(fromArguments: ["/Claude"]) == nil)
        #expect(ProcessArgumentParser.userDataDir(fromArguments: ["/Claude", "--user-data-dir="]) == nil)
        #expect(ProcessArgumentParser.userDataDir(fromArguments: ["/Claude", "--user-data-dir"]) == nil)
        // argv[0] is never treated as a switch.
        #expect(ProcessArgumentParser.userDataDir(fromArguments: ["--user-data-dir=/x"]) == nil)
    }

    @Test func parsesPsCommandLine() {
        let line = "/Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/me/Library/Application Support/X/app-data --other"
        #expect(ProcessArgumentParser.userDataDir(fromCommandLine: line) == "/Users/me/Library/Application Support/X/app-data")
        #expect(ProcessArgumentParser.userDataDir(fromCommandLine: "/a/Claude --user-data-dir=/x y") == "/x y")
        #expect(ProcessArgumentParser.userDataDir(fromCommandLine: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
    }
}

struct InstanceMatcherTests {
    let home = "/Users/tester-that-does-not-exist"
    var locations: ClaudeDefaultLocations { ClaudeDefaultLocations(homeDirectory: home) }

    var personal: Instance {
        Instance(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Personal",
                 appDataPath: home + "/.claude-instances/personal", claudeCodePath: home + "/.claude-personal")
    }

    var instances: [Instance] { [Instance.makeDefault(name: "Work", locations: locations), personal] }

    @Test func noArgumentMeansDefault() {
        #expect(InstanceMatcher.match(userDataDir: nil, instances: instances, locations: locations) == .known(Instance.defaultID))
        #expect(InstanceMatcher.match(userDataDir: "", instances: instances, locations: locations) == .known(Instance.defaultID))
    }

    @Test func explicitDefaultLocationMeansDefault() {
        let path = home + "/Library/Application Support/Claude/"
        #expect(InstanceMatcher.match(userDataDir: path, instances: instances, locations: locations) == .known(Instance.defaultID))
    }

    @Test func matchesKnownInstanceAfterStandardising() {
        for path in [home + "/.claude-instances/personal",
                     home + "/.claude-instances/personal/",
                     home + "/.claude-instances/./other/../personal",
                     "~/.claude-instances/Personal"] {
            #expect(InstanceMatcher.match(userDataDir: path, instances: instances, locations: locations) == .known(personal.id))
        }
    }

    @Test func unmatchedPathIsUnknown() {
        let result = InstanceMatcher.match(userDataDir: "/tmp/somewhere-else", instances: instances, locations: locations)
        guard case .unknown(let path) = result else {
            Issue.record("Expected unknown, got \(result)")
            return
        }
        #expect(path.hasSuffix("somewhere-else"))
    }

    @Test func matchesThroughSymlinks() throws {
        let temp = try TemporaryFolder()
        let real = try temp.makeFolder("real/app-data")
        try FileManager.default.createSymbolicLink(atPath: temp.path + "/link", withDestinationPath: temp.path + "/real")
        let instance = Instance(id: UUID(), name: "Linked", appDataPath: real, claudeCodePath: temp.path + "/cc")
        let result = InstanceMatcher.match(userDataDir: temp.path + "/link/app-data",
                                           instances: [instance], locations: locations)
        #expect(result == .known(instance.id))
    }
}
