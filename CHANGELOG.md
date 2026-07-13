# Changelog

All notable changes to QuotaBar are documented here.

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

[0.3.0]: https://github.com/patrickradulescu/QuotaBar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/patrickradulescu/QuotaBar/compare/da73a91...v0.2.0
[0.1.0]: https://github.com/patrickradulescu/QuotaBar/commit/da73a91
