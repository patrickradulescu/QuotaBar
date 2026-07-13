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

For AGY-in-terminal activation, QuotaBar reads only same-user PID, parent PID, process start time, executable path/file identity, and code-signing metadata through macOS process APIs. It validates both the file and the running process against Google's Developer ID requirement. It does not read terminal text, command lines, environment variables, TTY buffers, or shell history. The process-identity result is cached for ten minutes and polling occurs only while a supported terminal is frontmost.

## Provider boundary

- Codex usage comes from the documented `codex app-server` `account/rateLimits/read` method over a private stdio pipe.
- Claude usage comes from the official Claude Code `/usage` screen in an isolated safe-mode pseudo-terminal that exists only while a supported app is frontmost.
- Gemini usage is opt-in through AGY's official custom statusline callback. AGY invokes the bundled `QuotaBarAgyBridge`; QuotaBar never launches a hidden AGY session.
- The QuotaBar process never opens Codex authentication files, cookies, databases, or another app container.
- Provider stdout, stderr, and raw AGY statusline payloads are not persisted. Only normalized percentages, reset timestamps, AGY version, and observation time reach QuotaBar's cache/UI.
- Provider executables are resolved from fixed locations. Codex, Claude, and AGY must pass strict Developer ID signature checks before launch or setup is offered.
- Codex and Claude probes spawned by QuotaBar receive a minimal allowlisted environment so unrelated app environment values are not forwarded. The AGY bridge is different: AGY spawns it as the configured statusline command, so normal process semantics give it AGY's environment. The bridge code never reads, enumerates, logs, or persists environment variables.
- QuotaBar contains no automatic installer and no telemetry SDK.
- The user-initiated update checker makes one ephemeral HTTPS request to GitHub's public latest-release API. It accepts only published stable versions and the exact canonical tag URL, enforces its 256 KiB limit while streaming, and does not download or execute code.

Claude Code may update its own session/history metadata as part of an interactive `/usage` session. That storage remains managed by Anthropic's signed CLI; QuotaBar never opens it and reuses a single helper while the eligible app remains active. If the user explicitly chooses **Refresh Now** outside an eligible app, QuotaBar performs one bounded refresh and stops those helpers after at most 30 seconds.

After a crash, QuotaBar checks same-user process metadata for an orphaned `/usr/bin/script` process with parent PID 1. It sends `SIGTERM` only when the executable path, full expected safe-mode argument shape, and the `QuotaBar-Usage-Probe-v1` marker all match twice. Process arguments are never logged or persisted, ordinary Claude sessions do not match, and cleanup never uses `SIGKILL`.

AGY currently has no supported headless quota subcommand or public quota API. Its documented statusline callback is therefore the only automatic bridge QuotaBar supports. Setup is explicit: the user copies a `/statusline` command into AGY, replacing AGY's built-in/default statusline or any existing custom statusline while connected. `/statusline delete` disconnects the bridge and restores AGY's default statusline. The helper accepts at most 256 KiB on stdin, ignores normal `quota: null` startup events, validates only `gemini-5h` and `gemini-weekly`, and atomically writes a sanitized DTO as mode `0600` inside QuotaBar's mode `0700` Application Support directory. It does not persist account, working directory, conversation ID, prompt, third-party quota, environment variables, or the raw input.

Gemini values are the last quota report emitted by AGY, not a direct live read of the Antigravity GUI. QuotaBar treats a report as live for at most 30 minutes and rejects it once its reset has passed, but it cannot guarantee that the displayed value matches Settings → Models between callbacks.

Google documents the statusline command transport, but its current published field table omits the `quota` object emitted by AGY 1.1.1. The parser is intentionally strict and version-sensitive; **Open Antigravity Models…** remains available in every state. QuotaBar never reads Antigravity OAuth tokens, cookies, settings, databases, application containers, process tokens, private loopback APIs, or screen pixels.

Terminal activation is process-tree scoped, not tab scoped. If a supported terminal app is frontmost, a same-user, Google-signed AGY process in any of that app's tabs or windows may activate QuotaBar even when the visible tab is unrelated. QuotaBar does not read terminal contents to disambiguate the active tab.

QuotaBar will not install source-only updates automatically. A future one-click updater requires Developer-ID-signed and notarized binaries plus signed update metadata; until then, update installation remains an explicit action on the trusted GitHub release page.

The first local release reuses the installed official provider CLI and is intentionally not App-Sandboxed. This is still a smaller permission footprint than Full Disk Access, but it is not the final isolation boundary. The production roadmap is to place pinned provider helpers behind a sandboxed XPC interface that exposes only sanitized usage DTOs.

## Private Touch Bar API

Cross-application Touch Bar presentation is not available through public AppKit. The private selector bridge is isolated in `PrivateTouchBarBridge.swift`, does not load a private framework, and falls back safely when unavailable. This prevents Mac App Store distribution and may require maintenance after a macOS update.

## Reporting

Please open a private security advisory in the GitHub repository rather than a public issue for vulnerabilities.
