import Foundation

/// The launch arguments and environment of a process, as read from the kernel.
struct ProcessLaunchInfo: Equatable {
    var executablePath: String
    var arguments: [String]
    /// `nil` when the environment couldn't be read.
    var environment: [String: String]?
}

/// Pure parsing of process arguments. No system calls, so it can be unit tested.
enum ProcessArgumentParser {

    static let userDataDirFlag = "--user-data-dir"

    /// Parses the buffer returned by `sysctl` with `KERN_PROCARGS2`.
    ///
    /// Layout: a 32-bit `argc`, the executable path (NUL-terminated), padding
    /// NULs, then `argc` NUL-terminated arguments (including `argv[0]`), then
    /// NUL-terminated `KEY=value` environment strings.
    static func parseProcArgs2(_ buffer: [UInt8]) -> ProcessLaunchInfo? {
        guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return nil }

        var index = MemoryLayout<Int32>.size

        func readString() -> String? {
            guard index < buffer.count else { return nil }
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            let string = String(decoding: buffer[start..<index], as: UTF8.self)
            index += 1 // skip the NUL
            return string
        }

        guard let executable = readString() else { return nil }
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        for _ in 0..<argc {
            guard let arg = readString() else { return nil }
            arguments.append(arg)
        }

        var environment: [String: String] = [:]
        var sawEnvironment = false
        while index < buffer.count, let entry = readString(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            sawEnvironment = true
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }

        return ProcessLaunchInfo(
            executablePath: executable,
            arguments: arguments,
            environment: sawEnvironment ? environment : nil
        )
    }

    /// Finds `--user-data-dir` in an argument list. Accepts both
    /// `--user-data-dir=<path>` and `--user-data-dir <path>`. As in Chromium,
    /// the last occurrence wins. `argv[0]` is skipped.
    static func userDataDir(fromArguments arguments: [String]) -> String? {
        var result: String?
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            if arg.hasPrefix(userDataDirFlag + "=") {
                result = String(arg.dropFirst(userDataDirFlag.count + 1))
            } else if arg == userDataDirFlag, index + 1 < arguments.count {
                result = arguments[index + 1]
                index += 1
            }
            index += 1
        }
        if let value = result, value.isEmpty { return nil }
        return result
    }

    /// Fallback for the single string printed by `ps -o args=`, where the
    /// original argument boundaries are lost. The value runs from after
    /// `--user-data-dir=` up to the next ` -` that starts another switch, or the end.
    static func userDataDir(fromCommandLine commandLine: String) -> String? {
        let marker = userDataDirFlag + "="
        guard let range = commandLine.range(of: marker, options: .backwards) else { return nil }
        let rest = commandLine[range.upperBound...]
        let end = rest.range(of: " -")?.lowerBound ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// Which instance a running Claude belongs to.
enum DetectedInstance: Equatable {
    case known(UUID)
    /// Launched with a `--user-data-dir` that matches no instance.
    case unknown(path: String)
}

/// Pure matching of a `--user-data-dir` value against known instances.
enum InstanceMatcher {

    /// - Parameters:
    ///   - userDataDir: the raw value from the process's arguments, or `nil` if absent.
    ///   - instances: all instances, including the default one.
    static func match(
        userDataDir: String?,
        instances: [Instance],
        locations: ClaudeDefaultLocations = ClaudeDefaultLocations()
    ) -> DetectedInstance {
        guard let raw = userDataDir, !raw.isEmpty else {
            return .known(Instance.defaultID)
        }
        let path = PathStandardiser.standardise(raw, homeDirectory: locations.homeDirectory)

        let defaultAppData = PathStandardiser.standardise(locations.appData, homeDirectory: locations.homeDirectory)
        if PathComparison.isSame(path, defaultAppData) {
            return .known(Instance.defaultID)
        }

        for instance in instances where !instance.isDefault {
            let candidate = PathStandardiser.standardise(instance.appDataPath, homeDirectory: locations.homeDirectory)
            if PathComparison.isSame(path, candidate) {
                return .known(instance.id)
            }
        }
        return .unknown(path: path)
    }
}
