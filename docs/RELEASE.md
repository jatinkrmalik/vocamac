# VocaMac Release Process

## Overview

VocaMac uses GitHub Actions for CI/CD. Releases are triggered by pushing a version tag (e.g., `v0.1.0`). The release workflow builds the app, creates a DMG and ZIP archive, generates checksums, and publishes a draft GitHub Release.

## Versioning

We follow [Semantic Versioning](https://semver.org/):

```
vMAJOR.MINOR.PATCH
```

- **MAJOR** - Breaking changes or significant redesigns
- **MINOR** - New features, backward compatible
- **PATCH** - Bug fixes, minor improvements

Pre-release versions use suffixes: `v0.1.0-alpha`, `v0.1.0-beta.1`

## Release Checklist

### Before Tagging

1. **Ensure all PRs are merged** into `main`
2. **Verify CI passes** on the latest `main` commit
3. **Update version number** in all locations:
   - `scripts/build.sh` — both `CFBundleVersion` and `CFBundleShortVersionString` in the Info.plist template
   - `Sources/VocaMac/Views/SettingsView.swift` — version label in the About tab
   - `web/layouts/index.html` — `softwareVersion` in JSON-LD schema and hero version badge (two occurrences)
4. **Test locally**:
   ```bash
   ./scripts/build.sh release
   open VocaMac.app
   ```
5. **Verify core functionality**:
   - App appears in menu bar
   - Push-to-talk recording works
   - Transcription produces correct text
   - Text injection works at cursor
   - Settings dialog opens and all tabs function
   - Model download and switching works
   - Sound effects play on start/stop
6. **Review README** for accuracy

### Creating a Release

1. **Tag the release**:
   ```bash
   git tag -a v0.2.0 -m "VocaMac v0.2.0"
   git push origin v0.2.0
   ```

2. **GitHub Actions automatically**:
   - Imports the Developer ID certificate from repository secrets
   - Builds the release binary with Developer ID signing
   - Creates a beautiful branded DMG (`VocaMac-0.5.0-arm64.dmg`)
   - Notarizes with Apple and staples the ticket
   - Packages as ZIP (`VocaMac-0.5.0-arm64.zip`)
   - Generates SHA-256 checksums
   - Creates a **draft** GitHub Release with all artifacts

3. **Review the draft release** at https://github.com/jatinkrmalik/vocamac/releases
   - Edit release notes if needed
   - Verify artifacts are attached
   - **Publish** the release when ready

4. **Website auto-deploys** when the release is published (via `deploy-website.yml`)

## In-App Update Integration

VocaMac includes an in-app update checker powered by GitHub Releases:

- Automatic check on launch (throttled to once every 24 hours)
- Manual check via **Settings -> About -> Check for Updates...**
- If a new version is available, VocaMac downloads the latest `arm64` DMG with progress
- Downloaded DMG integrity is verified using GitHub's SHA-256 release digest
- App opens the DMG and guides users to drag/replace in Applications

This implementation reuses existing release artifacts and does not require extra appcast or Sparkle infrastructure.

## Release Artifacts

Each release produces:

| Artifact | Description |
|----------|-------------|
| `VocaMac-X.Y.Z-arm64.dmg` | DMG disk image with drag-to-Applications installer |
| `VocaMac-X.Y.Z-arm64.zip` | ZIP archive of VocaMac.app |
| `checksums.txt` | SHA-256 checksums for verification |

## Architecture Support

Currently **Apple Silicon (arm64) only**. The build runs on `macos-15` runners which are arm64.

For universal binary support (arm64 + x86_64) in the future:
```bash
swift build -c release --arch arm64 --arch x86_64
```

## Code Signing

- **Developer ID Application** certificate — auto-detected from Keychain locally, imported from secrets in CI
- **Notarized** with Apple — no Gatekeeper warnings for users
- DMG is stapled so notarization validates offline
- Permissions persist across updates (no more manual re-grants)

## CI Workflows

### `ci.yml` - Build & Test

- **Triggers**: Push to `main`, pull requests to `main`
- **Steps**: Debug build, test suite, release build, app bundle verification
- **Caching**: SPM dependencies cached for faster builds
- **Concurrency**: Cancels in-progress runs for the same branch

### `release.yml` - Release

- **Triggers**: Push of version tags (`v*`)
- **Steps**: Build, test, create DMG + ZIP, generate checksums, create draft release
- **Output**: Draft GitHub Release with downloadable artifacts

### `deploy-website.yml` - Website

- **Triggers**: Release published, manual dispatch
- **Steps**: Deploy `web/` directory to GitHub Pages

## Manual Release (Without CI)

If you need to create a release locally:

```bash
# Build the app, create signed + notarized DMG
make dmg
# Output: dist/VocaMac-X.Y.Z-arm64.dmg

# Create ZIP from the signed .app
ditto -c -k --sequesterRsrc --keepParent VocaMac.app "dist/VocaMac-X.Y.Z-arm64.zip"

# Generate checksums
cd dist && shasum -a 256 VocaMac-*.dmg VocaMac-*.zip > checksums.txt
```

Then upload the artifacts manually to the GitHub Release page.

## Hotfix Process

For critical bugs in a released version:

1. Create a branch from the release tag: `git checkout -b fix/critical-bug v0.2.0`
2. Fix the bug, commit, push
3. Create a PR to `main`
4. After merge, tag a patch release: `v0.1.1`
5. Push the tag to trigger the release workflow
