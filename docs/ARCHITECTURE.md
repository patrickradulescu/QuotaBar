# Architecture

```text
NSWorkspace frontmost-app events ──> GlobalTouchBarController
                                          │
                                          v
                                 PrivateTouchBarBridge
                                          │
                                          v
                                    NSTouchBar UI

Verified Codex/Claude CLI ──stdio──> provider adapter ──> sanitized ProviderUsage

AGY TUI ──statusline JSON/stdin──> bundled QuotaBarAgyBridge
                                         │
                                         v
                              agy-quota.json (0600 DTO)
                                         │
                                         v
                                AgyQuotaCacheClient
```

QuotaBar stays alive as one `LSUIElement` process. It presents the same strongly retained Touch Bar when an allowlisted AI application becomes frontmost and dismisses it when focus moves elsewhere. The process is never restarted during app switching.

## Clean-room boundary

This project is an original implementation. It does not include source code, artwork, resources, or decompiled output from What The Token. Observable platform behavior informed the product requirements; implementation and branding were created independently.

## Supported applications

- ChatGPT/Codex: `com.openai.codex`
- Claude Desktop: `com.anthropic.claudefordesktop`
- Google Antigravity: `com.google.antigravity` and `com.google.antigravity-ide`; live quota is opt-in through AGY's statusline callback, with Settings → Models retained as the manual fallback
- AGY in Terminal, iTerm2, Ghostty, WezTerm, Warp, Kitty, or Alacritty: eligible only while a same-user, Google-signed `agy` process is a descendant of the frontmost terminal process

Browser-tab detection is intentionally excluded because it would require browser integration or Accessibility access.

Terminal detection polls process metadata every 1.5 seconds only while a supported terminal is frontmost. It inspects same-user PID ancestry, executable path/file identity, and both static-file and live-process Developer ID validity; it does not inspect terminal contents. This is app/process-tree scoped rather than active-tab scoped, so AGY in any tab or window owned by the frontmost terminal app can activate QuotaBar even when another tab is visible. Detached tmux/server ancestry is intentionally not guessed.

## Update boundary

`Check for Updates…` uses an ephemeral, delegate-driven `URLSession` to read GitHub's public latest-release JSON. Version comparison, streaming size enforcement, status classification, and exact release-URL validation live in `QuotaBarCore`; only stable tags and the canonical repository tag path are accepted. The checker opens the release page but never downloads, extracts, executes, or replaces an app bundle. Automatic installation is deferred until the project has Developer ID signing, Apple notarization, and signed update metadata.

## AGY bridge boundary

QuotaBar does not spawn AGY. The user explicitly configures AGY's documented custom statusline command to run the universal helper inside `/Applications/QuotaBar.app`. That command replaces AGY's built-in/default statusline or any existing custom statusline while connected. Because AGY spawns the helper, it inherits AGY's process environment; the helper code never reads, enumerates, logs, or persists environment variables. Minimal allowlisted environments apply only to provider probes that QuotaBar spawns itself.

The helper decodes one bounded stdin payload in memory, selects only the two Gemini quota buckets, and writes a minimal normalized file. Missing/null/malformed events never erase the last good cache. The app independently validates file type, ownership, permissions, size, schema, freshness, fractions, and reset times before creating `ProviderUsage`. The UI represents the last report received from AGY, not a direct live read of the Antigravity GUI; reports are accepted for at most 30 minutes and can lag Settings → Models between callbacks.

QuotaBar never edits `~/.gemini/antigravity-cli/settings.json` or silently replaces a statusline command. Setup is an explicit copy/paste action. `/statusline delete` is the documented disconnect path and restores AGY's default statusline.

## Helper lifecycle

Provider helpers exist while their provider scope is active. A terminal AGY scope starts only the Gemini cache reader, never Codex or Claude. An explicit menu-bar **Refresh Now** click can start a one-shot all-provider refresh outside an allowlisted app; that scope expires after at most 30 seconds. Normal shutdown terminates direct children before QuotaBar exits. A force-quit can leave the Claude PTY adopted by launchd, so startup performs a narrowly scoped cleanup: PPID 1, `/usr/bin/script`, the expected safe-mode argument shape, and QuotaBar's unique probe marker must all match immediately before `SIGTERM` is sent.
