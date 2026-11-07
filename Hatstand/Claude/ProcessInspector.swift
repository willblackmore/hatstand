import Foundation
import Darwin

/// Thin wrappers around the system calls used to inspect other processes.
enum ProcessInspector {

    /// Reads a process's arguments and environment with `KERN_PROCARGS2`.
    static func launchInfo(pid: pid_t) -> ProcessLaunchInfo? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArgumentParser.parseProcArgs2(Array(buffer.prefix(size)))
    }

    /// The `--user-data-dir` a process was launched with. Uses `sysctl`, and
    /// falls back to `ps` if that fails. Returns `.success(nil)` when the flag
    /// is absent, and `.failure` when the arguments couldn't be read at all.
    static func userDataDir(pid: pid_t) -> Result<String?, Error> {
        if let info = launchInfo(pid: pid) {
            return .success(ProcessArgumentParser.userDataDir(fromArguments: info.arguments))
        }
        if let commandLine = psArguments(pid: pid) {
            return .success(ProcessArgumentParser.userDataDir(fromCommandLine: commandLine))
        }
        return .failure(CocoaError(.fileReadUnknown))
    }

    static func psArguments(pid: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "args=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    /// The executable path of a process, or `nil` if it has gone or can't be read.
    static func executablePath(pid: pid_t) -> String? {
        let capacity = 4 * Int(MAXPATHLEN) // PROC_PIDPATHINFO_MAXSIZE
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = proc_pidpath(pid, &buffer, UInt32(capacity))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Leave room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBytes { raw in
            proc_listallpids(raw.baseAddress, Int32(raw.count))
        }
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
    }

    /// Every process whose executable lives inside `bundlePath`.
    static func pids(insideBundle bundlePath: String) -> [pid_t] {
        let prefix = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
        return allPIDs().filter { pid in
            guard let path = executablePath(pid: pid) else { return false }
            return path.hasPrefix(prefix)
        }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
