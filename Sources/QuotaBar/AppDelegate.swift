import AppKit
import QuotaBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = UsageCoordinator()
    private let touchBarController = GlobalTouchBarController()
    private let updateChecker = UpdateChecker()
    private var statusItem: NSStatusItem?
    private var snapshots: [ProviderKind: ProviderUsage] = [:]
    private var isCheckingForUpdates = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        StaleHelperCleaner.terminateOrphanedClaudeProbes()
        configureStatusItem()

        coordinator.onChange = { [weak self] snapshots in
            self?.snapshots = snapshots
            self?.touchBarController.update(snapshots)
            NormalizedSnapshotWriter.write(snapshots)
            self?.rebuildMenu()
        }

        touchBarController.onEligibilityChange = { [weak self] isEligible in
            self?.coordinator.setEligibleApplicationActive(isEligible)
        }

        coordinator.start()
        touchBarController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBarController.stop()
        coordinator.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.50percent",
                accessibilityDescription: "QuotaBar"
            )
            button.image?.isTemplate = true
            button.toolTip = "QuotaBar — AI usage on Touch Bar"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "QuotaBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        ProviderKind.allCases.forEach { provider in
            let usage = snapshots[provider]
            let item = NSMenuItem(
                title: Self.menuTitle(provider: provider, usage: usage),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        if snapshots[.gemini]?.state == .actionRequired {
            let antigravity = NSMenuItem(
                title: "Open Antigravity Models…",
                action: #selector(openAntigravityModels),
                keyEquivalent: ""
            )
            antigravity.target = self
            menu.addItem(antigravity)
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = LoginItemController.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        let update = NSMenuItem(
            title: isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        )
        update.target = self
        update.isEnabled = !isCheckingForUpdates
        menu.addItem(update)

        let version = NSMenuItem(
            title: "Version \(Self.currentVersion)",
            action: nil,
            keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())

        let privacy = NSMenuItem(
            title: "Privacy: No Full Disk Access",
            action: nil,
            keyEquivalent: ""
        )
        privacy.isEnabled = false
        menu.addItem(privacy)

        let compatibility = NSMenuItem(
            title: touchBarController.isSupported ? "Touch Bar: Supported" : "Touch Bar: Menu-only fallback",
            action: nil,
            keyEquivalent: ""
        )
        compatibility.isEnabled = false
        menu.addItem(compatibility)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit QuotaBar",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func refreshNow() {
        coordinator.refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            try LoginItemController.setEnabled(!LoginItemController.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func openAntigravityModels() {
        let preferredBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let application = AntigravityApplicationLocator.locate(
                preferredBundleIdentifier: preferredBundleIdentifier
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard let application else {
                    self.showAlert(
                        message: "Antigravity is not available",
                        information: "Install the official Google Antigravity app, then try again.",
                        style: .warning
                    )
                    return
                }
                self.presentAntigravityInstructions(application: application)
            }
        }
    }

    private func presentAntigravityInstructions(application: AntigravityApplication) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let instructions = NSAlert()
        instructions.messageText = "View Gemini quota in Antigravity"
        instructions.informativeText = "After Antigravity opens, press Command–Comma and select Models. Google currently exposes the five-hour and weekly quota only inside the official app."
        instructions.alertStyle = .informational
        instructions.addButton(withTitle: "Open Antigravity")
        instructions.addButton(withTitle: "Cancel")
        guard instructions.runModal() == .alertFirstButtonReturn else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: application.url,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.showAlert(
                    message: "Could not open Antigravity",
                    information: error.localizedDescription,
                    style: .warning
                )
            }
        }
    }

    @objc private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        rebuildMenu()

        updateChecker.check(currentVersion: Self.currentVersion) { [weak self] result in
            guard let self else { return }
            self.isCheckingForUpdates = false
            self.rebuildMenu()

            switch result {
            case let .success(.updateAvailable(current, latest)):
                self.presentAvailableUpdate(current: current, latest: latest)
            case let .success(.upToDate(current, latest)):
                self.showAlert(
                    message: "QuotaBar is up to date",
                    information: "You are running \(current.description). The latest public release is \(latest.version.description).",
                    style: .informational
                )
            case .failure:
                self.showAlert(
                    message: "Could not check for updates",
                    information: "QuotaBar could not reach the public GitHub release feed. Check your internet connection and try again.",
                    style: .warning
                )
            }
        }
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func presentAvailableUpdate(current: ReleaseVersion, latest: GitHubRelease) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "QuotaBar \(latest.version.description) is available"
        alert.informativeText = "You are running \(current.description). QuotaBar will open the verified GitHub release page so you can review and install it. Automatic replacement remains disabled until releases are Developer ID-signed and notarized."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Release")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(latest.pageURL)
        }
    }

    private func showAlert(message: String, information: String, style: NSAlert.Style) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.alertStyle = style
        alert.runModal()
    }

    private static func menuTitle(provider: ProviderKind, usage: ProviderUsage?) -> String {
        guard let usage else {
            return "\(provider.displayName): Waiting…"
        }

        switch usage.state {
        case .loading:
            return "\(provider.displayName): Loading…"
        case .live:
            guard let primary = usage.primary else {
                return "\(provider.displayName): Live"
            }
            let used = Int(primary.usedPercent.rounded())
            let remaining = Int(primary.remainingPercent.rounded())
            if provider == .claude {
                var parts = ["5H \(used)% used", "\(remaining)% left"]
                if let weekly = usage.secondary {
                    parts.append("week all \(Int(weekly.usedPercent.rounded()))%")
                }
                if let fable = usage.namedWeeklyLimits?.first(where: {
                    $0.label.caseInsensitiveCompare("Fable") == .orderedSame
                }) {
                    parts.append("Fable \(Int(fable.window.usedPercent.rounded()))%")
                }
                return "Claude: " + parts.joined(separator: " · ")
            }
            return "\(provider.displayName): \(used)% used · \(remaining)% left"
        case .actionRequired:
            return "\(provider.displayName): \(usage.detail ?? "Open provider app")"
        case .unavailable:
            if provider == .gemini {
                return "Gemini: \(usage.detail ?? "Antigravity not installed")"
            }
            return "\(provider.displayName): Not configured"
        case .error:
            return "\(provider.displayName): Temporarily unavailable"
        }
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.3.0"
    }
}
