import Darwin
import Foundation

/// Detects only a same-user, Google-signed AGY process descended from the
/// frontmost terminal application. It never reads terminal text, command-line
/// arguments, environment variables, TTY buffers, or another process's files.
final class AgyProcessMonitor {
    private static let googleTeamIdentifier = "EQHXZ8M8AV"
    private static let signingIdentifier = "cli"
    private static let signatureCacheLifetime: TimeInterval = 10 * 60

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    private struct ProcessIdentity: Hashable {
        let pid: pid_t
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
    }

    private struct Verification {
        let path: String
        let identity: FileIdentity
        let verifiedAt: Date
    }

    private var verifiedProcesses: [ProcessIdentity: Verification] = [:]

    func hasVerifiedAgyDescendant(of terminalPID: pid_t) -> Bool {
        guard terminalPID > 1 else { return false }
        let now = Date()
        verifiedProcesses = verifiedProcesses.filter {
            now.timeIntervalSince($0.value.verifiedAt) < Self.signatureCacheLifetime
        }

        // Build one same-user parent map, then resolve executable paths only
        // for descendants of the terminal. proc_pidpath for every process was
        // unnecessarily expensive on a 1.5-second foreground poll.
        var processInfos: [pid_t: proc_bsdinfo] = [:]
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for pid in allProcessIDs() where pid != terminalPID {
            guard let info = processInfo(for: pid), info.pbi_uid == geteuid() else {
                continue
            }
            processInfos[pid] = info
            childrenByParent[pid_t(info.pbi_ppid), default: []].append(pid)
        }

        var stack = childrenByParent[terminalPID] ?? []
        var visited = Set<pid_t>()
        while let pid = stack.popLast() {
            guard visited.insert(pid).inserted else { continue }
            stack.append(contentsOf: childrenByParent[pid] ?? [])

            guard let info = processInfos[pid],
                  let path = executablePath(for: pid),
                  URL(fileURLWithPath: path).lastPathComponent == "agy" else {
                continue
            }
            if isVerifiedAgy(pid: pid, info: info, path: path, now: now) {
                return true
            }
        }
        return false
    }

    private func isVerifiedAgy(
        pid: pid_t,
        info: proc_bsdinfo,
        path: String,
        now: Date
    ) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let processIdentity = ProcessIdentity(
            pid: pid,
            startedSeconds: info.pbi_start_tvsec,
            startedMicroseconds: info.pbi_start_tvusec
        )
        guard let identity = fileIdentity(at: resolved) else { return false }
        if let verification = verifiedProcesses[processIdentity],
           verification.path == resolved.path,
           verification.identity == identity,
           now.timeIntervalSince(verification.verifiedAt) < Self.signatureCacheLifetime {
            return true
        }

        guard FileManager.default.isExecutableFile(atPath: resolved.path),
              CodeSignatureVerifier.hasValidSignature(
                  resolved,
                  teamIdentifier: Self.googleTeamIdentifier,
                  signingIdentifier: Self.signingIdentifier
              ),
              CodeSignatureVerifier.hasValidRunningSignature(
                  pid: pid,
                  teamIdentifier: Self.googleTeamIdentifier,
                  signingIdentifier: Self.signingIdentifier
              ),
              fileIdentity(at: resolved) == identity else {
            return false
        }
        verifiedProcesses[processIdentity] = Verification(
            path: resolved.path,
            identity: identity,
            verifiedAt: now
        )
        return true
    }

    private func fileIdentity(at url: URL) -> FileIdentity? {
        var metadata = stat()
        guard url.path.withCString({ stat($0, &metadata) }) == 0 else {
            return nil
        }
        return FileIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            size: UInt64(metadata.st_size),
            modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            changedSeconds: Int64(metadata.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(metadata.st_ctimespec.tv_nsec)
        )
    }

    private func allProcessIDs() -> [pid_t] {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else { return [] }

        let stride = MemoryLayout<pid_t>.stride
        var pids = [pid_t](
            repeating: 0,
            count: (Int(requiredBytes) / stride) + 64
        )
        let capacity = Int32(pids.count * stride)
        let usedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, capacity)
        guard usedBytes > 0 else { return [] }
        return Array(pids.prefix(Int(usedBytes) / stride)).filter { $0 > 1 }
    }

    private func processInfo(for pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return info
    }

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
