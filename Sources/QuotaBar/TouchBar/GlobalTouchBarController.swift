import AppKit
import os
import QuotaBarCore

final class GlobalTouchBarController {
    private struct ApplicationIdentity: Equatable {
        let bundleIdentifier: String
        let processIdentifier: pid_t

        init?(_ application: NSRunningApplication?) {
            guard let application, let bundleIdentifier = application.bundleIdentifier else {
                return nil
            }
            self.bundleIdentifier = bundleIdentifier
            processIdentifier = application.processIdentifier
        }
    }

    private static let reconciliationInterval: TimeInterval = 2
    private let logger = Logger(
        subsystem: "com.patrickradulescu.QuotaBar",
        category: "touchbar"
    )
    private let allowedBundleIdentifiers: Set<String> = [
        "com.openai.codex",
        "com.anthropic.claudefordesktop",
        "com.google.antigravity",
        "com.google.antigravity-ide"
    ]
    private let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty"
    ]

    private let touchBarDelegate = QuotaTouchBarDelegate()
    private lazy var touchBar: NSTouchBar = touchBarDelegate.makeTouchBar()
    private let agyProcessMonitor = AgyProcessMonitor()
    private let agyProcessQueue = DispatchQueue(
        label: "com.patrickradulescu.quotabar.agy-process-monitor",
        qos: .utility
    )
    var onActiveProvidersChange: ((Set<ProviderKind>) -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var frontmostReconciliationTimer: Timer?
    private var lastFrontmostIdentity: ApplicationIdentity?
    private var terminalMonitorTimer: Timer?
    private var terminalProbeGeneration = 0
    private var terminalProbeInFlight = false
    private var frontmostTerminalPID: pid_t?
    private var isPresented = false
    private var activeProviders = Set<ProviderKind>()
    private var sessionIsAvailable = true

    var isSupported: Bool { PrivateTouchBarBridge.isSupported }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            self?.handleFrontmostApplicationChange(application)
        })

        [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification
        ].forEach { name in
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.sessionDidBecomeUnavailable()
            })
        }

        [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification
        ].forEach { name in
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.sessionDidBecomeAvailable()
            })
        }

        reconcileFrontmostApplication(force: true)

        // NSWorkspace can briefly report nil/the launching LSUIElement while
        // applicationDidFinishLaunching runs. A lightweight identity watchdog
        // repairs a missed startup activation and any later lost notification
        // without repeatedly restarting providers for an unchanged app.
        let timer = Timer(
            fire: Date().addingTimeInterval(0.5),
            interval: Self.reconciliationInterval,
            repeats: true
        ) { [weak self] _ in
            self?.reconcileFrontmostApplication()
        }
        frontmostReconciliationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        frontmostReconciliationTimer?.invalidate()
        frontmostReconciliationTimer = nil
        lastFrontmostIdentity = nil
        stopTerminalMonitoring()
        setActiveProviders([])
        dismiss()
    }

    func update(_ snapshots: [ProviderKind: ProviderUsage]) {
        touchBarDelegate.update(snapshots)
    }

    private func reconcileFrontmostApplication(force: Bool = false) {
        guard sessionIsAvailable else { return }
        let application = NSWorkspace.shared.frontmostApplication
        let identity = ApplicationIdentity(application)
        guard force || identity != lastFrontmostIdentity else { return }
        handleFrontmostApplicationChange(application)
    }

    private func handleFrontmostApplicationChange(
        _ application: NSRunningApplication?
    ) {
        lastFrontmostIdentity = ApplicationIdentity(application)
        frontmostApplicationDidChange(application)
    }

    private func frontmostApplicationDidChange(_ application: NSRunningApplication?) {
        stopTerminalMonitoring()
        guard sessionIsAvailable,
              let bundleIdentifier = application?.bundleIdentifier else {
            setActiveProviders([])
            dismiss()
            return
        }

        if allowedBundleIdentifiers.contains(bundleIdentifier) {
            setActiveProviders(Set(ProviderKind.allCases))
            present()
        } else if terminalBundleIdentifiers.contains(bundleIdentifier),
                  let application {
            startTerminalMonitoring(processIdentifier: application.processIdentifier)
        } else {
            setActiveProviders([])
            dismiss()
        }
    }

    private func sessionDidBecomeUnavailable() {
        sessionIsAvailable = false
        lastFrontmostIdentity = nil
        stopTerminalMonitoring()
        setActiveProviders([])
        dismiss()
    }

    private func sessionDidBecomeAvailable() {
        sessionIsAvailable = true
        reconcileFrontmostApplication(force: true)
    }

    private func setActiveProviders(_ providers: Set<ProviderKind>) {
        guard providers != activeProviders else { return }
        activeProviders = providers
        onActiveProvidersChange?(providers)
    }

    private func startTerminalMonitoring(processIdentifier: pid_t) {
        frontmostTerminalPID = processIdentifier
        setActiveProviders([])
        dismiss()
        probeFrontmostTerminal()
        let timer = Timer(
            timeInterval: 1.5,
            repeats: true
        ) { [weak self] _ in
            self?.probeFrontmostTerminal()
        }
        terminalMonitorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTerminalMonitoring() {
        terminalMonitorTimer?.invalidate()
        terminalMonitorTimer = nil
        frontmostTerminalPID = nil
        terminalProbeGeneration += 1
        terminalProbeInFlight = false
    }

    private func probeFrontmostTerminal() {
        guard sessionIsAvailable,
              !terminalProbeInFlight,
              let terminalPID = frontmostTerminalPID else {
            return
        }

        terminalProbeInFlight = true
        terminalProbeGeneration += 1
        let generation = terminalProbeGeneration
        agyProcessQueue.async { [weak self] in
            guard let self else { return }
            let isAgyActive = self.agyProcessMonitor.hasVerifiedAgyDescendant(
                of: terminalPID
            )
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.terminalProbeGeneration,
                      self.frontmostTerminalPID == terminalPID else {
                    return
                }
                self.terminalProbeInFlight = false
                if isAgyActive {
                    // A terminal AGY session authorizes only the Gemini cache
                    // reader. It must never launch Codex or Claude probes.
                    self.setActiveProviders([.gemini])
                    self.present()
                } else {
                    self.setActiveProviders([])
                    self.dismiss()
                }
            }
        }
    }

    private func present() {
        guard !isPresented, isSupported else { return }
        isPresented = PrivateTouchBarBridge.present(touchBar)
        if isPresented {
            logger.info("Presented QuotaBar Touch Bar")
        }
    }

    private func dismiss() {
        guard isPresented else { return }
        PrivateTouchBarBridge.dismiss(touchBar)
        isPresented = false
        logger.info("Dismissed QuotaBar Touch Bar")
    }
}
