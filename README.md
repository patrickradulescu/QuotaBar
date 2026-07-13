# QuotaBar

QuotaBar is a small macOS menu-bar app that shows AI usage on the Touch Bar only while a supported AI app is frontmost. It is an original, clean-room implementation with its own code and artwork.

![macOS](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-22c55e)

## What it does

- Shows used and remaining quota with a compact progress bar.
- Appears for Codex/ChatGPT and Claude Desktop. A Gemini activation slot is reserved but disabled in the first release.
- Dismisses immediately when you switch to Safari or another unrelated app.
- Keeps one menu-bar process alive; it does not replace the normal Touch Bar permanently.
- Offers a menu-bar fallback when the private Touch Bar presenter is unavailable.

## Provider status

| Provider | Source | Status |
| --- | --- | --- |
| Codex | Documented `codex app-server` method `account/rateLimits/read` | Supported |
| Claude | Official Claude Code `/usage` screen in an isolated safe-mode PTY | Beta |
| Gemini | Visible model-quota parser is prepared; runtime adapter intentionally disabled | Planned |

QuotaBar never implements provider authentication. Sign in with each supported provider's official app or CLI first.

Gemini remains disabled in v0.1 because Gemini CLI can initialize user hooks, extensions, skills, and MCP servers before showing quota. It will be enabled only after those startup integrations can be isolated reliably without copying or reading Google credentials.

## Privacy and security

QuotaBar does **not** request Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation, administrator access, or your passwords.

- Provider commands are launched directly, never through a shell.
- Raw terminal output is kept in memory only and is never logged or written to disk.
- Only normalized provider state, percentages, and reset times are cached in `~/Library/Application Support/QuotaBar/status.json`.
- There is no analytics SDK, telemetry, automatic updater, or remote QuotaBar server.
- Supported signed provider binaries are checked before launch where macOS signing information is available.
- Child processes receive a minimal environment rather than the parent app's full environment.

Claude's signed CLI may update its own session/history metadata because `/usage` is an interactive command. QuotaBar reuses one Claude process while an eligible app stays frontmost, never opens those files itself, and stops the helper as soon as you switch away.

See [SECURITY.md](SECURITY.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the threat model and implementation boundary.

## Requirements

- A Touch Bar Mac running macOS 13 or later.
- Swift 6 / Xcode Command Line Tools to build from source.
- The official Codex and/or Claude Code CLI already authenticated.

## Build and install

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
./scripts/install-local.sh
```

The installer builds a universal (Apple silicon + Intel), ad-hoc-signed local app, copies it to `/Applications/QuotaBar.app`, and opens it. Enable **Launch at Login** from the menu-bar gauge if desired.

For development:

```bash
swift build
swift test
./scripts/build-app.sh
```

## Uninstall

Turn off **Launch at Login**, quit QuotaBar, then remove:

```bash
rm -rf /Applications/QuotaBar.app
rm -rf "$HOME/Library/Application Support/QuotaBar"
rm -rf "$HOME/Library/Caches/com.patrickradulescu.QuotaBar"
```

## Distribution caveat

Public AppKit can show an `NSTouchBar` only for the active owning app. Cross-application presentation therefore uses one isolated private AppKit selector. QuotaBar does not load a private framework, but this means it is not suitable for the Mac App Store and may need maintenance after a macOS update.

GitHub source builds are ad-hoc signed. A downloadable release for other Macs should be universal, Developer-ID signed, hardened, and notarized before distribution.

## Clean-room statement

QuotaBar does not contain source code, artwork, resources, credentials, or decompiled output from What The Token or any other third-party quota app. Observable behavior was used only to define product requirements; the implementation and branding were created independently.

## License

MIT © 2026 Patrick Radulescu.
