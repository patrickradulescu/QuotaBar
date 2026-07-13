# Security

QuotaBar is designed to display normalized quota numbers without handling provider passwords or OAuth tokens.

## Permissions

QuotaBar does **not** request or require:

- Full Disk Access
- Accessibility
- Screen Recording
- Input Monitoring
- Automation
- administrator or root access

The app monitors frontmost application changes through the public `NSWorkspace` notification API.

## Provider boundary

- Codex usage comes from the documented `codex app-server` `account/rateLimits/read` method over a private stdio pipe.
- Claude usage comes from the official Claude Code `/usage` screen in an isolated safe-mode pseudo-terminal that exists only while a supported app is frontmost.
- The QuotaBar process never opens Codex authentication files, cookies, databases, or another app container.
- Provider stdout and stderr are not persisted. Only normalized percentages and reset timestamps reach the UI.
- Provider executables are resolved from fixed locations. Codex and Claude must pass strict Developer ID signature checks before launch.
- Provider helpers receive a minimal allowlisted environment so unrelated shell secrets are never forwarded.
- QuotaBar contains no automatic installer and no telemetry SDK.
- The user-initiated update checker makes one ephemeral HTTPS request to GitHub's public latest-release API. It accepts only published stable versions and a release URL under `https://github.com/patrickradulescu/QuotaBar/releases/`; it does not download or execute code.

Claude Code may update its own session/history metadata as part of an interactive `/usage` session. That storage remains managed by Anthropic's signed CLI; QuotaBar never opens it and reuses a single helper while the eligible app remains active.

After a crash, QuotaBar checks same-user process metadata for an orphaned `/usr/bin/script` process with parent PID 1. It sends `SIGTERM` only when the executable path, full expected safe-mode argument shape, and the `QuotaBar-Usage-Probe-v1` marker all match twice. Process arguments are never logged or persisted, ordinary Claude sessions do not match, and cleanup never uses `SIGKILL`.

Gemini quota collection is intentionally disabled because Google Antigravity currently has no supported headless quota command or public machine-readable API. QuotaBar verifies the installed Antigravity bundle against Google LLC's Developer ID, then directs the user to Settings → Models. It never reads Antigravity OAuth tokens, cookies, databases, application containers, process tokens, private loopback APIs, or screen pixels.

QuotaBar will not install source-only updates automatically. A future one-click updater requires Developer-ID-signed and notarized binaries plus signed update metadata; until then, update installation remains an explicit action on the trusted GitHub release page.

The first local release reuses the installed official provider CLI and is intentionally not App-Sandboxed. This is still a smaller permission footprint than Full Disk Access, but it is not the final isolation boundary. The production roadmap is to place pinned provider helpers behind a sandboxed XPC interface that exposes only sanitized usage DTOs.

## Private Touch Bar API

Cross-application Touch Bar presentation is not available through public AppKit. The private selector bridge is isolated in `PrivateTouchBarBridge.swift`, does not load a private framework, and falls back safely when unavailable. This prevents Mac App Store distribution and may require maintenance after a macOS update.

## Reporting

Please open a private security advisory in the GitHub repository rather than a public issue for vulnerabilities.
