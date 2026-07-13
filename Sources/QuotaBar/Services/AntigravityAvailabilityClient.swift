import Foundation
import QuotaBarCore

/// Detects a genuine Google-signed Antigravity installation without opening
/// its credentials, databases, application container, or private local APIs.
/// Google does not currently expose a supported headless quota endpoint, so
/// the user is directed to the official Models screen for exact values.
final class AntigravityAvailabilityClient: UsageProviderClient {
    let provider: ProviderKind = .gemini
    var onUpdate: ((ProviderUsage) -> Void)?

    private static let minimumValidationInterval: TimeInterval = 10 * 60

    private let validationQueue = DispatchQueue(
        label: "com.patrickradulescu.quotabar.antigravity-validation",
        qos: .utility
    )
    private var isRunning = false
    private var cachedSnapshot: ProviderUsage?
    private var lastValidatedAt: Date?

    private static func currentSnapshot() -> ProviderUsage {
        if AntigravityApplicationLocator.locate() != nil {
            return .actionRequired(
                .gemini,
                detail: "Open Antigravity Settings → Models"
            )
        }

        return .unavailable(.gemini, detail: "Antigravity not installed")
    }

    func start() {
        validationQueue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            self.validateIfNeededOnQueue()
        }
    }

    func refresh() {
        validationQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.validateIfNeededOnQueue()
        }
    }

    func stop() {
        // Signature validation can take more than a second on large bundles.
        // Never wait for it synchronously while the user is switching apps.
        validationQueue.async { [weak self] in
            self?.isRunning = false
        }
    }

    private func validateIfNeededOnQueue() {
        let now = Date()
        let snapshot: ProviderUsage
        if let cachedSnapshot,
           let lastValidatedAt,
           now.timeIntervalSince(lastValidatedAt) < Self.minimumValidationInterval {
            snapshot = cachedSnapshot
        } else {
            snapshot = Self.currentSnapshot()
            cachedSnapshot = snapshot
            lastValidatedAt = now
        }

        guard isRunning else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }
}
