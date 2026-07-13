import Darwin
import Foundation
import QuotaBarCore

/// Reads only the normalized cache written by QuotaBarAgyBridge. The bridge is
/// an explicit AGY statusline integration; this client never opens AGY's
/// settings, credentials, history, logs, databases, or private APIs.
final class AgyQuotaCacheClient: UsageProviderClient {
    let provider: ProviderKind = .gemini
    var onUpdate: ((ProviderUsage) -> Void)?

    private static let maximumCacheBytes = 64 * 1_024
    private static let maximumSnapshotAge: TimeInterval = 30 * 60

    private let ioQueue = DispatchQueue(
        label: "com.patrickradulescu.quotabar.agy-quota-cache",
        qos: .utility
    )
    private let lifecycleLock = NSLock()
    private var isRunning = false
    private var readGeneration = 0
    private var runGeneration = 0
    private var lifecycleGeneration = 0

    func start() {
        lifecycleLock.lock()
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        lifecycleLock.unlock()

        ioQueue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            self.runGeneration = generation
            self.beginReadCycleOnQueue(runGeneration: generation)
        }
    }

    func refresh() {
        ioQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.beginReadCycleOnQueue(runGeneration: self.runGeneration)
        }
    }

    func stop() {
        lifecycleLock.lock()
        lifecycleGeneration += 1
        lifecycleLock.unlock()

        ioQueue.async { [weak self] in
            self?.isRunning = false
            self?.readGeneration += 1
        }
    }

    private func beginReadCycleOnQueue(runGeneration: Int) {
        readGeneration += 1
        readAndPublishOnQueue(
            generation: readGeneration,
            runGeneration: runGeneration,
            attempt: 0
        )
    }

    private func readAndPublishOnQueue(
        generation: Int,
        runGeneration: Int,
        attempt: Int
    ) {
        guard isRunning,
              generation == readGeneration,
              runGeneration == self.runGeneration else { return }
        let destination = Self.cacheURL
        let cacheExists = FileManager.default.fileExists(atPath: destination.path)

        if let data = secureCacheData(at: destination),
           let snapshot = try? AgyQuotaCacheCodec.decode(data),
           let usage = snapshot.normalizedUsage(
               maximumAge: Self.maximumSnapshotAge
           ) {
            publish(usage, runGeneration: runGeneration)
            return
        }

        if attempt == 0 {
            if CommandLocator.agy() != nil {
                publish(.actionRequired(
                    .gemini,
                    detail: cacheExists
                        ? "Open AGY to refresh quota"
                        : "Set up AGY quota from the menu"
                ), runGeneration: runGeneration)
            } else if AntigravityApplicationLocator.locate() != nil {
                publish(.actionRequired(
                    .gemini,
                    detail: "Open Antigravity Settings → Models"
                ), runGeneration: runGeneration)
            } else {
                publish(.unavailable(
                    .gemini,
                    detail: "AGY CLI not installed"
                ), runGeneration: runGeneration)
            }
        }

        // AGY emits the first valid statusline quota shortly after its startup
        // transitions. Retry briefly so setup does not appear stuck for the
        // coordinator's full one-minute refresh interval.
        guard attempt < 9 else { return }
        ioQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.readAndPublishOnQueue(
                generation: generation,
                runGeneration: runGeneration,
                attempt: attempt + 1
            )
        }
    }

    private func secureCacheData(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let fileSize = values.fileSize,
        fileSize <= Self.maximumCacheBytes,
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
        ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
        let data = try? Data(contentsOf: url),
        data.count <= Self.maximumCacheBytes else {
            return nil
        }
        return data
    }

    private func publish(_ usage: ProviderUsage, runGeneration: Int) {
        guard isRunning, runGeneration == self.runGeneration else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lifecycleLock.lock()
            let isCurrent = self.lifecycleGeneration == runGeneration
            self.lifecycleLock.unlock()
            guard isCurrent else { return }
            self.onUpdate?(usage)
        }
    }

    private static var cacheURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("QuotaBar", isDirectory: true)
        .appendingPathComponent("agy-quota.json")
    }
}
