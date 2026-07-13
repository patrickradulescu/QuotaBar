import Foundation
import QuotaBarCore

enum NormalizedSnapshotWriter {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let generatedAt: Date
        let providers: [ProviderUsage]
    }

    static func write(_ snapshots: [ProviderKind: ProviderUsage]) {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("QuotaBar", isDirectory: true)
        let destination = directory.appendingPathComponent("status.json")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            let envelope = Envelope(
                schemaVersion: 1,
                generatedAt: Date(),
                providers: ProviderKind.allCases.compactMap { provider in
                    guard let usage = snapshots[provider] else { return nil }
                    return ProviderUsage(
                        provider: usage.provider,
                        state: usage.state,
                        primary: usage.primary,
                        secondary: usage.secondary,
                        observedAt: usage.observedAt,
                        detail: nil
                    )
                }
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(envelope).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            // The dashboard remains fully functional if its optional diagnostic cache fails.
        }
    }
}
