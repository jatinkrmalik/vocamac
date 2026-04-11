# VocaMac v0.5.0

## In-App Updates

VocaMac can now check for updates automatically and download the latest release right from the app. On launch (once every 24 hours), it queries GitHub Releases and shows an update banner in the menu bar popover when a newer version is available. One-click download with real-time progress, SHA-256 integrity verification, and guided drag-to-Applications install.

Manual check available at **Settings > About > Check for Updates**.

## Improved Mic Indicator Placement

The floating mic indicator now uses a 4-tier Accessibility API fallback strategy instead of the previous binary caret-or-mouse approach:

| Tier | Method | Works In |
|------|--------|----------|
| 1 | Exact caret position | Native AppKit/SwiftUI apps |
| 2 | Focused element bounds | Electron apps, terminal emulators |
| 3 | Focused window position | Almost all apps |
| 4 | Mouse cursor | Last resort |

This significantly improves indicator placement in apps like **Cursor** and **iTerm2** that don't implement full AX text attributes.

## Other Changes

- **Fixed large-v3 model incorrectly marked as unsupported** due to substring matching against disabled model variants. The recommendation engine now checks the supported list directly and falls back to the best supported model when the default is too large for the device.
- **Improved log rotation efficiency** — reduced max log size from 5 MB to 1 MB, cached date formatter, eliminated per-write `fsync`, and added proper error handling during rotation.
- **Tests run 2x faster** with zero system side effects — all service dependencies (audio, hotkeys, sounds, permissions) are now injected via protocols with mock implementations.

## Full Changelog

- feat: add in-app GitHub Releases update flow (#96)
- fix: add tiered fallback for cursor indicator positioning (#93)
- fix: large-v3 model incorrectly marked as unsupported due to substring matching bug (#92)
- fix: improve log rotation efficiency and reduce max log size from 5MB to 1MB (#94)
- fix: inject mock services in tests to eliminate system side effects (#95)
