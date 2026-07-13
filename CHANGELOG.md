# Changelog

All notable changes to QuotaBar are documented here.

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

[0.2.0]: https://github.com/patrickradulescu/QuotaBar/compare/da73a91...v0.2.0
[0.1.0]: https://github.com/patrickradulescu/QuotaBar/commit/da73a91
