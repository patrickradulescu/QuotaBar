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
- Gemini: activation/parser reserved; collection disabled until CLI startup isolation is proven

Browser-tab detection is intentionally excluded because it would require browser integration or Accessibility access.

## Helper lifecycle

Provider helpers exist only while an allowlisted application is frontmost. Normal shutdown terminates direct children before QuotaBar exits. A force-quit can leave the Claude PTY adopted by launchd, so startup performs a narrowly scoped cleanup: PPID 1, `/usr/bin/script`, the expected safe-mode argument shape, and QuotaBar's unique probe marker must all match immediately before `SIGTERM` is sent.
