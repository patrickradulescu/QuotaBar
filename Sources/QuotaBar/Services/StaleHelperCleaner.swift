import Darwin
import Foundation

enum ClaudeProbeIdentity {
    static let sessionName = "QuotaBar-Usage-Probe-v1"

    static func matchesScriptArguments(_ arguments: [String]) -> Bool {
        guard arguments.count == 12,
              arguments[0] == "/usr/bin/script",
              arguments[1] == "-q",
              arguments[2] == "/dev/null",
              arguments[3].hasSuffix("/claude") else {
            return false
        }

        return Array(arguments[4...]) == [
            "--safe-mode",
            "--ax-screen-reader",
            "--strict-mcp-config",
            "--tools",
            "",
            "--no-chrome",
            "--name",
            sessionName
        ]
    }
}

/// Removes only a Claude PTY that was explicitly named by QuotaBar and whose
/// parent has already died. This handles app crashes or force-replacement
/// without matching ordinary Claude Code sessions.
enum StaleHelperCleaner {
    static func terminateOrphanedClaudeProbes() {
        for pid in matchingOrphanPIDs() {
            // Verify the complete identity immediately before signalling to
            // narrow the PID-reuse window. Never escalate to SIGKILL.
            guard isMatchingOrphan(pid) else { continue }
            _ = Darwin.kill(pid, SIGTERM)
        }
    }

    private static func matchingOrphanPIDs() -> Set<Int32> {
        Set(allProcessIDs().filter(isMatchingOrphan))
    }

    private static func allProcessIDs() -> [Int32] {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else { return [] }

        let stride = MemoryLayout<Int32>.stride
        var pids = [Int32](
            repeating: 0,
            count: (Int(requiredBytes) / stride) + 64
        )
        let capacity = Int32(pids.count * stride)
        let usedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, capacity)
        guard usedBytes > 0 else { return [] }

        return Array(pids.prefix(Int(usedBytes) / stride)).filter { $0 > 1 }
    }

    private static func isMatchingOrphan(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
              info.pbi_uid == geteuid(),
              info.pbi_ppid == 1,
              executablePath(for: pid) == "/usr/bin/script",
              let arguments = processArguments(for: pid) else {
            return false
        }
        return ClaudeProbeIdentity.matchesScriptArguments(arguments)
    }

    private static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processArguments(for pid: Int32) -> [String]? {
        var mib = [Int32(CTL_KERN), Int32(KERN_PROCARGS2), pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size,
              size <= 64 * 1_024 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        var available = size
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctl(
                &mib,
                UInt32(mib.count),
                bytes.baseAddress,
                &available,
                nil,
                0
            )
        }
        guard result == 0,
              available >= MemoryLayout<Int32>.size else {
            return nil
        }
        buffer.removeSubrange(available..<buffer.count)

        var argumentCount: Int32 = 0
        withUnsafeMutableBytes(of: &argumentCount) { destination in
            buffer.withUnsafeBytes { source in
                destination.copyBytes(from: source.prefix(MemoryLayout<Int32>.size))
            }
        }
        guard argumentCount > 0, argumentCount <= 128 else { return nil }

        var index = MemoryLayout<Int32>.size
        guard let executableEnd = buffer[index...].firstIndex(of: 0) else { return nil }
        index = executableEnd + 1
        while index < buffer.count, buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        arguments.reserveCapacity(Int(argumentCount))
        for _ in 0..<argumentCount {
            guard index <= buffer.count,
                  let end = buffer[index...].firstIndex(of: 0) else {
                return nil
            }
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }
}
