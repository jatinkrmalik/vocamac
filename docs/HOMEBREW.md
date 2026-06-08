# VocaMac Homebrew Distribution Guide

## Overview

VocaMac is distributed via Homebrew as a **cask**, not a formula. This distinction matters:

- **Formula** — for command-line tools and libraries built from source
- **Cask** — for pre-built macOS applications distributed as binaries (`.app`, `.dmg`)

Since VocaMac is a native macOS `.app` distributed as a signed and notarized DMG via GitHub Releases, a cask is the correct packaging format. Users get the exact same binary as the manual download, installed with a single command.

## Quick Start (For Users)

```bash
# Install
brew tap jatinkrmalik/vocamac
brew install --cask vocamac

# Upgrade to latest version
brew upgrade --cask vocamac

# Uninstall
brew uninstall --cask vocamac
brew untap jatinkrmalik/vocamac
```

After installation, VocaMac appears in `/Applications/VocaMac.app`. Launch it from Spotlight or the Applications folder.

## Nightly Builds

A nightly cask is also available, built daily from the latest `main` branch:

```bash
brew install --cask vocamac-nightly
```

The nightly cask uses `version :latest` and `sha256 :no_check` because the DMG content changes with every daily build. Homebrew will always fetch the newest artifact without needing a cask definition update.

**Stable and nightly conflict.** Both casks install to `/Applications/VocaMac.app`, so you can only have one installed at a time. Uninstall the stable cask before installing nightly, or vice versa:

```bash
brew uninstall --cask vocamac
brew install --cask vocamac-nightly
```

Nightly is a pre-release build intended for testing and early feedback. Use the stable release for daily use.

No auto-update workflow is needed for the nightly cask. The cask definition itself never changes. Homebrew re-downloads the latest DMG each time `brew upgrade --cask vocamac-nightly` runs.

## Custom Tap Setup

The cask lives in a custom tap repository: `jatinkrmalik/homebrew-vocamac`.

### Creating the Tap Repository

1. Create a new public GitHub repository named `homebrew-vocamac` under the `jatinkrmalik` account
2. The repository must follow Homebrew tap naming: `homebrew-<name>`
3. Clone it locally:
   ```bash
   git clone https://github.com/jatinkrmalik/homebrew-vocamac.git
   cd homebrew-vocamac
   ```
4. Create the cask directory structure:
   ```bash
   mkdir -p Casks
   ```
5. Copy the cask file from the main repo:
   ```bash
   cp /path/to/vocamac/homebrew/Casks/vocamac.rb Casks/
   ```
6. Commit and push:
   ```bash
   git add Casks/vocamac.rb
   git commit -m "chore: add vocamac cask"
   git push origin main
   ```

Users can then install with `brew tap jatinkrmalik/vocamac && brew install --cask vocamac`.

## Testing Locally

Before pushing a cask update to the tap, test it locally against a real DMG:

```bash
brew install --cask ./homebrew/Casks/vocamac.rb
```

This installs the cask directly from the file path, bypassing the tap. It requires a real DMG to exist at the URL specified in the cask (i.e., a published GitHub Release).

To verify the installation:

```bash
ls /Applications/VocaMac.app
brew info --cask vocamac
```

To uninstall after testing:

```bash
brew uninstall --cask vocamac
```

## Manual Cask Update

When a new VocaMac version ships, the cask needs two updates: the `version` string and the `sha256` checksum.

1. Download the new DMG:
   ```bash
   curl -L -o VocaMac-X.Y.Z-arm64.dmg \
     https://github.com/jatinkrmalik/vocamac/releases/download/vX.Y.Z/VocaMac-X.Y.Z-arm64.dmg
   ```

2. Compute the SHA-256:
   ```bash
   shasum -a 256 VocaMac-X.Y.Z-arm64.dmg
   ```

3. Update `homebrew/Casks/vocamac.rb`:
   - Change `version "X.Y.Z"` to the new version
   - Replace `sha256 :no_check` with `sha256 "<computed-sha256>"`

4. Test locally (see [Testing Locally](#testing-locally) above)

5. Commit and push to the tap repository:
   ```bash
   cd /path/to/homebrew-vocamac
   git add Casks/vocamac.rb
   git commit -m "chore: update vocamac to vX.Y.Z"
   git push origin main
   ```

## Auto-Update Workflow

The repository includes `.github/workflows/update-homebrew-cask.yml`, which automates cask updates on every release publish.

### How It Works

1. The workflow triggers on `release` event with `types: [published]`
2. It extracts the version tag (e.g., `v0.6.2` → `0.6.2`)
3. It downloads the DMG from the release assets
4. It computes the SHA-256 checksum
5. It updates `homebrew/Casks/vocamac.rb` with the new version and sha256
6. It pushes the change to the `jatinkrmalik/homebrew-vocamac` tap repository

### Required GitHub Secret

The workflow needs a Personal Access Token with `repo` scope to push to the tap repository:

- **Secret name:** `HOMEBREW_TAP_TOKEN`
- **Scope:** `repo` (full control of private and public repositories)
- **Set at:** Repository Settings → Secrets and variables → Actions

Generate the token at [github.com/settings/tokens](https://github.com/settings/tokens) with the `repo` scope. The token owner must have write access to `jatinkrmalik/homebrew-vocamac`.

## Submitting to homebrew-cask

Once VocaMac meets the notability requirements, the cask can be submitted to the official [homebrew-cask](https://github.com/Homebrew/homebrew-cask) repository, eliminating the need for a custom tap.

### Requirements

- **75+ GitHub stars** on the repository
- **Signed and notarized** DMG (VocaMac already meets this)
- **Stable release** (not a pre-release or nightly)
- **Active maintenance** (recent commits, responsive maintainer)

### Submission Process

1. Fork [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask)
2. Create a branch: `git checkout -b add-vocamac`
3. Run `brew create --cask <dmg-url>` to generate the cask file
4. Place it in `Casks/v/vocamac.rb` (note the subdirectory structure)
5. Test: `brew install --cask ./Casks/v/vocamac.rb`
6. Commit and open a PR against `Homebrew/homebrew-cask`
7. Respond to reviewer feedback

Once merged, users install with just `brew install --cask vocamac` — no tap required.

## Zap Behavior

Running `brew uninstall --zap vocamac` removes the app **and** all associated user data:

```ruby
zap trash: [
  "~/Library/Application Support/VocaMac",   # Downloaded models, user config
  "~/Library/Caches/com.vocamac.app",        # Cached data
  "~/Library/Preferences/com.vocamac.app.plist",  # UserDefaults/preferences
  "~/Library/Saved Application State/com.vocamac.app.savedState",  # Window state
]
```

This is useful for a clean reinstall or when troubleshooting. A plain `brew uninstall --cask vocamac` only removes the `.app` bundle and leaves user data intact.

## Troubleshooting

### Cask install fails with "SHA256 mismatch"

The checksum in the cask file doesn't match the downloaded DMG. This happens when the cask hasn't been updated for a new release.

**Fix:** Update the cask manually (see [Manual Cask Update](#manual-cask-update)) or wait for the auto-update workflow to complete.

### "It seems there is already an App at..."

A previous installation exists at `/Applications/VocaMac.app`.

**Fix:** Remove the existing app first:
```bash
rm -rf /Applications/VocaMac.app
brew install --cask vocamac
```

### Cask not found after `brew tap`

The tap repository may not exist or the cask file is missing.

**Fix:** Verify the tap:
```bash
brew tap --repair jatinkrmalik/vocamac
ls "$(brew --prefix)/Homebrew/Library/Taps/jatinkrmalik/homebrew-vocamac/Casks/"
```

### App won't launch after Homebrew install

Homebrew installs the app to `/Applications/VocaMac.app` — it behaves identically to a manual DMG install. If the app won't launch:

1. Check Gatekeeper: `spctl --assess /Applications/VocaMac.app`
2. If quarantined: `xattr -d com.apple.quarantine /Applications/VocaMac.app`
3. Grant permissions in System Settings → Privacy & Security

### Auto-update workflow fails

Check the workflow run logs in the main repository's Actions tab. Common causes:

- `HOMEBREW_TAP_TOKEN` secret is missing or expired
- The tap repository doesn't exist or the token lacks write access
- The release DMG asset name doesn't match the expected pattern
