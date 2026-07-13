# Changelog

All notable changes to QuotaBar are documented here.

## [0.4.1] - 2026-07-14

### Fixed

- Reconciled the actual frontmost application shortly after launch and every two seconds, so QuotaBar recovers when macOS misses the activation notification for an app that was already open during startup.
- Compared both bundle identifier and process identifier during reconciliation, avoiding provider restarts while still detecting an app relaunch with the same bundle identifier.
- Moved provider refresh, manual-refresh expiry, terminal monitoring, and frontmost reconciliation timers to the common run-loop modes so opening a menu no longer pauses lifecycle maintenance.

### Changed

- Bumped the app version to 0.4.1 (build 5).

## [0.4.0] - 2026-07-14

### Added

- Opt-in Gemini quota collection through AGY's official custom statusline callback.
- A universal bundled `QuotaBarAgyBridge` that keeps only Gemini five-hour/weekly fractions, reset times, AGY version, and observation time.
- **Set Up AGY Quota…** instructions with explicit copy/paste consent, disclosure that setup replaces AGY's default/custom statusline, and `/statusline delete` recovery to the default.
- Precise sub-one-percent Gemini display, weekly-only plan support, and a permanent **Open Antigravity Models…** fallback.
- Touch Bar activation in supported terminals only when their process tree contains a same-user, Google-signed `agy` executable.
- Network-flow tests for current/newer releases, malformed feeds, rate limits, server failures, oversized responses, timeout, and offline behavior.
- A release-version invariant that rejects tags which do not match the app plist version.

### Changed

- Hardened **Check for Updates…** with streaming response limits and distinct user messages for network, timeout, rate-limit, server, and untrusted-feed failures.
- Made **Refresh Now** perform a bounded one-shot refresh outside supported apps instead of silently doing nothing; terminal AGY activation starts only the Gemini cache reader.
- Gemini cache data older than 30 minutes or beyond its reset is no longer presented as live.
- Clarified that Gemini shows the last quota report emitted by AGY and may lag the Antigravity GUI between callbacks.
- Bumped the app version to 0.4.0 (build 4).

### Security

- QuotaBar does not launch a hidden AGY process, edit AGY settings, or read Google credentials, logs, databases, private APIs, or screen pixels.
- The AGY helper accepts bounded stdin, never persists the raw payload/account/workspace/conversation, and writes only a mode-`0600` normalized DTO inside a mode-`0700` directory.
- Terminal activation validates both AGY's executable file and the live process against Google's Developer ID requirement, with cache invalidation on process/file identity changes.
- Documented that the AGY-spawned bridge inherits AGY's environment but never reads, enumerates, logs, or persists environment variables; minimal environments apply only to app-spawned probes.
- The update checker now stops oversized responses during transfer instead of checking only after a full download.

## [0.3.0] - 2026-07-13

### Added

- Google Antigravity and Antigravity IDE activation using their current bundle identifiers.
- Strict Google Developer ID verification before offering the Antigravity handoff.
- An **Open Antigravity Models…** menu action for the official five-hour and weekly quota screen.
- A user-initiated **Check for Updates…** flow backed by GitHub's public stable-release API.
- Semantic version and trusted release-URL validation tests.

### Changed

- Replaced Gemini's misleading `OFFLINE` state with an explicit `OPEN MODELS` action when a signed Antigravity installation is present.
- Removed the unused legacy Gemini CLI Pro/Flash daily-quota parser, which did not match Antigravity's current quota model.
- Bumped the normalized status cache to schema version 3 for the new `actionRequired` provider state.
- Bumped the app version to 0.3.0 (build 3).

### Security

- QuotaBar does not read Antigravity credentials, databases, private localhost services, process tokens, or screen contents.
- Source-only releases are never downloaded or executed automatically; the update checker opens only the canonical GitHub release page.

## [0.2.0] - 2026-07-13

### Added

- Distinct `5H`, `WK`, and `FABLE` labels for Claude usage on the Touch Bar.
- Parsing for Claude's current `Weekly limits`, `All models`, and model-specific layout.
- Support for relative session resets such as `in 1 hr 26 min` and weekday resets such as `Fri 9:00 PM`.
- Named weekly limits in the normalized local status schema.

### Changed

- The menu-bar summary now identifies Claude's five-hour, all-model weekly, and Fable weekly percentages explicitly.
- The app version is now 0.2.0 (build 2).

## [0.1.0] - 2026-07-13

### Added

- Initial clean-room QuotaBar implementation.
- App-scoped Touch Bar presentation for Codex/ChatGPT and Claude Desktop.
- Signed provider CLI verification, minimal helper environments, and sanitized local status caching.

[0.4.1]: https://github.com/patrickradulescu/QuotaBar/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/patrickradulescu/QuotaBar/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/patrickradulescu/QuotaBar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/patrickradulescu/QuotaBar/compare/da73a91...v0.2.0
[0.1.0]: https://github.com/patrickradulescu/QuotaBar/commit/da73a91
