import AppKit
import QuotaBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = UsageCoordinator()
    private let touchBarController = GlobalTouchBarController()
    private var statusItem: NSStatusItem?
    private var snapshots: [ProviderKind: ProviderUsage] = [:]

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

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
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
            return "\(provider.displayName): \(used)% used · \(remaining)% left"
        case .unavailable:
            return "\(provider.displayName): Not configured"
        case .error:
            return "\(provider.displayName): Temporarily unavailable"
        }
    }
}
