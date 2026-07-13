# Architecture

```text
NSWorkspace frontmost-app events ──> GlobalTouchBarController
                                          │
                                          v
                                 PrivateTouchBarBridge
                                          │
                                          v
                                    NSTouchBar UI

Verified official provider CLI ──stdio──> provider adapter ──> sanitized ProviderUsage
```

QuotaBar stays alive as one `LSUIElement` process. It presents the same strongly retained Touch Bar when an allowlisted AI application becomes frontmost and dismisses it when focus moves elsewhere. The process is never restarted during app switching.

## Clean-room boundary

This project is an original implementation. It does not include source code, artwork, resources, or decompiled output from What The Token. Observable platform behavior informed the product requirements; implementation and branding were created independently.

## Supported applications

- ChatGPT/Codex: `com.openai.codex`
- Claude Desktop: `com.anthropic.claudefordesktop`
- Google Antigravity: `com.google.antigravity` and `com.google.antigravity-ide`; the Google-signed bundle is detected and the user is directed to Settings → Models because no supported headless quota API exists

Browser-tab detection is intentionally excluded because it would require browser integration or Accessibility access.

## Update boundary

`Check for Updates…` uses an ephemeral `URLSession` to read GitHub's public latest-release JSON. Version comparison and release-URL validation live in `QuotaBarCore`; only stable tags and the canonical repository release path are accepted. The checker opens the release page but never downloads, extracts, executes, or replaces an app bundle. Automatic installation is deferred until the project has Developer ID signing, Apple notarization, and signed update metadata.

## Helper lifecycle

Provider helpers exist only while an allowlisted application is frontmost. Normal shutdown terminates direct children before QuotaBar exits. A force-quit can leave the Claude PTY adopted by launchd, so startup performs a narrowly scoped cleanup: PPID 1, `/usr/bin/script`, the expected safe-mode argument shape, and QuotaBar's unique probe marker must all match immediately before `SIGTERM` is sent.
