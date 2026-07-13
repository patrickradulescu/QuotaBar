import AppKit
import os
import QuotaBarCore

final class GlobalTouchBarController {
    private let logger = Logger(
        subsystem: "com.patrickradulescu.QuotaBar",
        category: "touchbar"
    )
    private let allowedBundleIdentifiers: Set<String> = [
        "com.openai.codex",
        "com.anthropic.claudefordesktop",
        "com.google.Gemini"
    ]

    private let touchBarDelegate = QuotaTouchBarDelegate()
    private lazy var touchBar: NSTouchBar = touchBarDelegate.makeTouchBar()
    var onEligibilityChange: ((Bool) -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var isPresented = false
    private var isEligible = false
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
            self?.frontmostApplicationDidChange(application)
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

        frontmostApplicationDidChange(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        setEligible(false)
        dismiss()
    }

    func update(_ snapshots: [ProviderKind: ProviderUsage]) {
        touchBarDelegate.update(snapshots)
    }

    private func frontmostApplicationDidChange(_ application: NSRunningApplication?) {
        guard sessionIsAvailable,
              let bundleIdentifier = application?.bundleIdentifier else {
            setEligible(false)
            dismiss()
            return
        }

        if allowedBundleIdentifiers.contains(bundleIdentifier) {
            setEligible(true)
            present()
        } else {
            setEligible(false)
            dismiss()
        }
    }

    private func sessionDidBecomeUnavailable() {
        sessionIsAvailable = false
        setEligible(false)
        dismiss()
    }

    private func sessionDidBecomeAvailable() {
        sessionIsAvailable = true
        frontmostApplicationDidChange(NSWorkspace.shared.frontmostApplication)
    }

    private func setEligible(_ eligible: Bool) {
        guard eligible != isEligible else { return }
        isEligible = eligible
        onEligibilityChange?(eligible)
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
