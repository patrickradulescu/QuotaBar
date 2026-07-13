import Foundation
import QuotaBarCore

final class UsageCoordinator {
    var onChange: (([ProviderKind: ProviderUsage]) -> Void)?

    private(set) var snapshots: [ProviderKind: ProviderUsage] = [
        .codex: .loading(.codex),
        .claude: .loading(.claude),
        .gemini: .unavailable(.gemini, detail: "Provider not configured")
    ]

    private let providers: [UsageProviderClient]
    private var refreshTimer: Timer?
    private var isRunning = false
    private var isEligibleApplicationActive = false
    private var providersAreRunning = false

    init(providers: [UsageProviderClient] = [CodexAppServerClient(), ClaudeUsageClient()]) {
        self.providers = providers
        providers.forEach { provider in
            provider.onUpdate = { [weak self] usage in
                guard let self else { return }
                self.snapshots[usage.provider] = usage
                self.onChange?(self.snapshots)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        onChange?(snapshots)
        reconcileProviderLifecycle()
    }

    func setEligibleApplicationActive(_ active: Bool) {
        guard active != isEligibleApplicationActive else { return }
        isEligibleApplicationActive = active
        reconcileProviderLifecycle()
    }

    func refresh() {
        guard isRunning, isEligibleApplicationActive else { return }
        providers.forEach { $0.refresh() }
    }

    func stop() {
        isRunning = false
        isEligibleApplicationActive = false
        stopProviders()
    }

    private func reconcileProviderLifecycle() {
        guard isRunning, isEligibleApplicationActive else {
            stopProviders()
            return
        }

        guard !providersAreRunning else { return }
        providersAreRunning = true
        providers.forEach { $0.start() }

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopProviders() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard providersAreRunning else { return }
        providersAreRunning = false
        providers.forEach { $0.stop() }
    }
}
