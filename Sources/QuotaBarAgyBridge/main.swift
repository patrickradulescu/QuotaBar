import Darwin
import Foundation
import QuotaBarCore

private let maximumInputBytes = 256 * 1_024
private let fileManager = FileManager.default

private enum BridgeError: Error {
    case inputTooLarge
    case unsafeDirectory
    case unsafeCache
}

private func readBoundedStandardInput() throws -> Data {
    var result = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 8 * 1_024),
          !chunk.isEmpty {
        guard result.count + chunk.count <= maximumInputBytes else {
            throw BridgeError.inputTooLarge
        }
        result.append(chunk)
    }
    return result
}

private func cacheDirectory() throws -> URL {
    let directory = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("QuotaBar", isDirectory: true)

    if fileManager.fileExists(atPath: directory.path) {
        let values = try directory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw BridgeError.unsafeDirectory
        }
    }

    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path
    )

    let attributes = try fileManager.attributesOfItem(atPath: directory.path)
    guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
          ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else {
        throw BridgeError.unsafeDirectory
    }
    return directory
}

private func loadCache(from destination: URL) -> AgyQuotaSnapshot? {
    guard fileManager.fileExists(atPath: destination.path),
          let values = try? destination.resourceValues(forKeys: [
              .isRegularFileKey,
              .isSymbolicLinkKey,
              .fileSizeKey
          ]),
          values.isRegularFile == true,
          values.isSymbolicLink != true,
          (values.fileSize ?? maximumInputBytes + 1) <= maximumInputBytes,
          let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
          ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
          let data = try? Data(contentsOf: destination),
          data.count <= maximumInputBytes else {
        return nil
    }
    return try? AgyQuotaCacheCodec.decode(data)
}

private func save(_ snapshot: AgyQuotaSnapshot, to destination: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
        let values = try destination.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BridgeError.unsafeCache
        }
    }

    let data = try AgyQuotaCacheCodec.encode(snapshot)
    try data.write(to: destination, options: .atomic)
    try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: destination.path
    )
}

_ = umask(0o077)

var latestSnapshot: AgyQuotaSnapshot?
var cacheDestination: URL?
do {
    let directory = try cacheDirectory()
    let destination = directory.appendingPathComponent("agy-quota.json")
    cacheDestination = destination
    let input = try readBoundedStandardInput()
    let existing = loadCache(from: destination)

    if let parsed = try AgyStatusPayloadParser.parse(data: input) {
        if let existing,
           !AgyQuotaCachePolicy.shouldPersist(
               incoming: parsed,
               replacing: existing
           ) {
            // AGY can invoke a statusline several times in a burst. Coalesce
            // identical reports briefly, then refresh observedAt so a running
            // AGY remains current while a stopped AGY expires after 30 minutes.
            latestSnapshot = existing
        } else {
            try save(parsed, to: destination)
            latestSnapshot = parsed
        }
    } else {
        // AGY emits `quota: null` during normal startup transitions. Keep the
        // last valid normalized snapshot instead of erasing it.
        latestSnapshot = loadCache(from: destination)
    }
} catch {
    // A statusline helper must never disrupt AGY. Errors are deliberately not
    // logged because even diagnostics could accidentally capture account data.
    if let cacheDestination {
        latestSnapshot = loadCache(from: cacheDestination)
    }
}

if let latestSnapshot,
   latestSnapshot.normalizedUsage(maximumAge: 30 * 60) != nil {
    print(latestSnapshot.compactStatusLine)
} else if latestSnapshot != nil {
    print("QuotaBar · Gemini quota stale")
} else {
    print("QuotaBar · Gemini quota pending")
}
