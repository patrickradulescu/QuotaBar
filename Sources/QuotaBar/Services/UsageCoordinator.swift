import Foundation
import QuotaBarCore

final class UsageCoordinator {
    var onChange: (([ProviderKind: ProviderUsage]) -> Void)?

    private static let geminiMaximumSnapshotAge: TimeInterval = 30 * 60
    private static let manualRefreshLifetime: TimeInterval = 30

    private(set) var snapshots: [ProviderKind: ProviderUsage] = [
        .codex: .loading(.codex),
        .claude: .loading(.claude),
        .gemini: .loading(.gemini)
    ]

    private let providers: [ProviderKind: UsageProviderClient]
    private var refreshTimer: Timer?
    private var manualRefreshTimer: Timer?
    private var geminiExpiryTimer: Timer?
    private var isRunning = false
    private var activeProviders = Set<ProviderKind>()
    private var manuallyRefreshingProviders = Set<ProviderKind>()
    private var runningProviders = Set<ProviderKind>()

    init(providers: [UsageProviderClient] = [
        CodexAppServerClient(),
        ClaudeUsageClient(),
        AgyQuotaCacheClient()
    ]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map {
            ($0.provider, $0)
        })
        providers.forEach { provider in
            provider.onUpdate = { [weak self] usage in
                guard let self else { return }
                self.snapshots[usage.provider] = usage
                if usage.provider == .gemini {
                    self.scheduleGeminiExpiry(for: usage)
                }
                self.onChange?(self.snapshots)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        expireGeminiSnapshotIfNeeded()
        onChange?(snapshots)
        reconcileProviderLifecycle()
    }

    func setActiveProviders(_ providers: Set<ProviderKind>) {
        guard providers != activeProviders else { return }
        activeProviders = providers
        expireGeminiSnapshotIfNeeded()
        reconcileProviderLifecycle()
        onChange?(snapshots)
    }

    func refresh() {
        guard isRunning else { return }
        expireGeminiSnapshotIfNeeded()

        if !activeProviders.isEmpty {
            activeProviders.forEach { providers[$0]?.refresh() }
            return
        }

        // A menu click is explicit consent to perform one bounded refresh even
        // when no supported app is frontmost. This avoids a clickable no-op
        // without keeping provider helpers alive in unrelated applications.
        manuallyRefreshingProviders = Set(providers.keys)
        reconcileProviderLifecycle()
        manuallyRefreshingProviders.forEach { providers[$0]?.refresh() }

        manualRefreshTimer?.invalidate()
        let timer = Timer(
            timeInterval: Self.manualRefreshLifetime,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.manuallyRefreshingProviders.removeAll()
            self.reconcileProviderLifecycle()
        }
        manualRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        isRunning = false
        activeProviders.removeAll()
        manuallyRefreshingProviders.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil
        manualRefreshTimer?.invalidate()
        manualRefreshTimer = nil
        geminiExpiryTimer?.invalidate()
        geminiExpiryTimer = nil
        reconcileProviderLifecycle()
    }

    private func reconcileProviderLifecycle() {
        let desiredProviders = isRunning
            ? activeProviders.union(manuallyRefreshingProviders)
            : []

        for provider in runningProviders.subtracting(desiredProviders) {
            providers[provider]?.stop()
        }
        for provider in desiredProviders.subtracting(runningProviders) {
            providers[provider]?.start()
        }
        runningProviders = desiredProviders

        if activeProviders.isEmpty {
            refreshTimer?.invalidate()
            refreshTimer = nil
        } else if refreshTimer == nil {
            let timer = Timer(
                timeInterval: 60,
                repeats: true
            ) { [weak self] _ in
                guard let self else { return }
                self.activeProviders.forEach { self.providers[$0]?.refresh() }
            }
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func scheduleGeminiExpiry(for usage: ProviderUsage) {
        geminiExpiryTimer?.invalidate()
        geminiExpiryTimer = nil
        guard usage.state == .live else { return }

        let ageDeadline = usage.observedAt.addingTimeInterval(
            Self.geminiMaximumSnapshotAge
        )
        let resetDeadlines = [usage.primary?.resetsAt, usage.secondary?.resetsAt]
            .compactMap { $0 }
        let deadline = resetDeadlines.reduce(ageDeadline, min)

        guard deadline > Date() else {
            expireGeminiSnapshotIfNeeded()
            return
        }

        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.expireGeminiSnapshotIfNeeded()
            self.onChange?(self.snapshots)
        }
        geminiExpiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func expireGeminiSnapshotIfNeeded(now: Date = Date()) {
        guard let usage = snapshots[.gemini], usage.state == .live else { return }
        let isTooOld = usage.observedAt > now.addingTimeInterval(5 * 60)
            || now.timeIntervalSince(usage.observedAt) > Self.geminiMaximumSnapshotAge
        let isPastReset = [usage.primary?.resetsAt, usage.secondary?.resetsAt]
            .compactMap { $0 }
            .contains { $0 <= now }
        guard isTooOld || isPastReset else {
            scheduleGeminiExpiry(for: usage)
            return
        }

        geminiExpiryTimer?.invalidate()
        geminiExpiryTimer = nil
        snapshots[.gemini] = .actionRequired(
            .gemini,
            detail: AgyQuotaUsageDetail.stale
        )
    }
}
