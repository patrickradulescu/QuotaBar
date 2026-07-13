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

        touchBarController.onActiveProvidersChange = { [weak self] providers in
            self?.coordinator.setActiveProviders(providers)
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

        let agyPresentation = AgyQuotaMenuPresentation(
            usage: snapshots[.gemini]
        )
        if let statusTitle = agyPresentation.statusTitle {
            let status = NSMenuItem(
                title: statusTitle,
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
        }
        if let actionTitle = agyPresentation.actionTitle {
            let action = NSMenuItem(
                title: actionTitle,
                action: #selector(setUpAgyQuota),
                keyEquivalent: ""
            )
            action.target = self
            menu.addItem(action)
        }

        // Keep the official UI fallback available even when the bridge is live
        // or a future AGY payload no longer parses.
        let antigravity = NSMenuItem(
            title: "Open Antigravity Models…",
            action: #selector(openAntigravityModels),
            keyEquivalent: ""
        )
        antigravity.target = self
        menu.addItem(antigravity)

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

    @objc private func setUpAgyQuota() {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("QuotaBarAgyBridge")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            showAlert(
                message: "AGY bridge is unavailable",
                information: "Reinstall the current QuotaBar release and try again.",
                style: .warning
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let agyURL = CommandLocator.agy()
            DispatchQueue.main.async {
                guard let self else { return }
                guard agyURL != nil else {
                    self.presentAgyDownloadPrompt()
                    return
                }
                self.presentAgySetupInstructions(helperURL: helperURL)
            }
        }
    }

    private func presentAgyDownloadPrompt() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Official AGY CLI not found"
        alert.informativeText = "Install and sign in to Google's Antigravity CLI first. QuotaBar accepts only a Google Developer ID-signed agy executable."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Google Download")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://antigravity.google/download#antigravity-cli") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentAgySetupInstructions(helperURL: URL) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let command = "/statusline \(Self.shellQuoted(helperURL.path))"
        let alert = NSAlert()
        alert.messageText = "Connect AGY quota to QuotaBar"
        alert.informativeText = "Copy the command below and paste it into the AGY prompt:\n\n\(command)\n\nAGY will send status updates to QuotaBar's bundled helper. The helper stores only Gemini quota fractions, reset times, AGY version, and observation time in QuotaBar's private cache. It never stores the raw payload, account, workspace, or conversation.\n\nAGY supports one statusline command, so this replaces its default display or any custom statusline. Use /statusline delete in AGY to disconnect and restore the default."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Setup Command")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        showAlert(
            message: "AGY setup command copied",
            information: "Paste it into the AGY prompt and press Return. Then choose Refresh Now in QuotaBar if the values do not appear within a minute.",
            style: .informational
        )
    }

    private func presentAntigravityInstructions(application: AntigravityApplication) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let instructions = NSAlert()
        instructions.messageText = "View Gemini quota in Antigravity"
        instructions.informativeText = "After Antigravity opens, press Command–Comma and select Models. This official screen remains the fallback for exact five-hour and weekly values."
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
            case let .failure(error):
                self.presentUpdateError(error)
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

    private func presentUpdateError(_ error: Error) {
        let message: String
        let information: String

        switch error as? UpdateChecker.CheckError {
        case .invalidCurrentVersion:
            message = "Could not verify this QuotaBar version"
            information = "The installed app has invalid version metadata. Reinstall QuotaBar from its official release."
        case .responseTooLarge, .invalidReleaseFeed:
            message = "GitHub returned an untrusted release feed"
            information = "QuotaBar rejected the response and did not open or run anything. Try again later or visit the repository manually."
        case .rateLimited:
            message = "GitHub temporarily limited update checks"
            information = "Wait a few minutes, then choose Check for Updates again."
        case .serverUnavailable:
            message = "GitHub releases are temporarily unavailable"
            information = "The GitHub service returned a server error. Try again later."
        case .timedOut:
            message = "The update check timed out"
            information = "Check your connection and try again. QuotaBar made no changes to the app."
        case .networkUnavailable:
            message = "Could not reach GitHub"
            information = "Check your internet connection and try again."
        case .invalidResponse, .none:
            message = "Could not check for updates"
            information = "GitHub returned an unexpected response. Try again later."
        }

        showAlert(message: message, information: information, style: .warning)
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
            if provider == .gemini {
                let window = primary.windowMinutes == 300 ? "5H" : "week"
                var parts = [
                    "\(window) \(formatPercent(primary.usedPercent))% used",
                    "\(formatPercent(primary.remainingPercent))% left"
                ]
                if let weekly = usage.secondary {
                    parts.append("week \(formatPercent(weekly.usedPercent))% used")
                }
                return "Gemini: " + parts.joined(separator: " · ")
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
            ?? "0.4.2"
    }

    private static func formatPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped > 0, clamped < 1 {
            return String(format: "%.2f", clamped)
        }
        if clamped != clamped.rounded() {
            return String(format: "%.1f", clamped)
        }
        return String(Int(clamped))
    }

    private static func shellQuoted(_ value: String) -> String {
        // AGY executes the statusline through a shell. Always quote the bundle
        // path instead of trying to maintain a partial metacharacter allowlist.
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
