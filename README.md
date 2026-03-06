<p align="center">
  <img src="web/logo.png" alt="VocaMac" width="128" height="128">
</p>

<h1 align="center">VocaMac</h1>

<p align="center"><strong>Your voice, your Mac, your privacy. Open-source dictation powered by AI.</strong></p>

<div align="center">
  
[![Build & Test](https://github.com/jatinkrmalik/vocamac/actions/workflows/ci.yml/badge.svg)](https://github.com/jatinkrmalik/vocamac/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)](https://github.com/jatinkrmalik/vocamac)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/jatinkrmalik/vocamac?include_prereleases&label=Release)](https://github.com/jatinkrmalik/vocamac/releases)

[![Powered by WhisperKit](https://img.shields.io/badge/Powered%20by-WhisperKit-blueviolet.svg)](https://github.com/argmaxinc/WhisperKit)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Optimized-black.svg?logo=apple&logoColor=white)](https://github.com/jatinkrmalik/vocamac)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Local-brightgreen.svg)](https://github.com/jatinkrmalik/vocamac)
[![Works Offline](https://img.shields.io/badge/Works-Offline-success.svg)](https://github.com/jatinkrmalik/vocamac)

[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/jatinkrmalik/vocamac/pulls)
[![GitHub Issues](https://img.shields.io/github/issues/jatinkrmalik/vocamac)](https://github.com/jatinkrmalik/vocamac/issues)
[![GitHub Stars](https://img.shields.io/github/stars/jatinkrmalik/vocamac?style=social)](https://github.com/jatinkrmalik/vocamac/stargazers)
[![Twitter Follow](https://img.shields.io/twitter/follow/jatinkrmalik?style=social)](https://x.com/intent/user?screen_name=jatinkrmalik)

</div>

Speak. It types. 100% offline, open-source voice-to-text for macOS - powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit). No cloud, no subscriptions, no data leaves your device. Just hold a hotkey, speak, and your words appear wherever your cursor is.

---

## 📸 Screenshots

<p align="center">
  <img src="docs/screenshots/popover-panel.png" alt="VocaMac Popover" width="400">
  <br>
  <em>Menu bar popover with status and controls</em>
</p>

<p align="center">
  <img src="docs/screenshots/menu-bar-idle.png" alt="Menu Bar - Idle" width="250">
  &nbsp;&nbsp;
  <img src="docs/screenshots/menu-bar-recording.png" alt="Menu Bar - Recording" width="250">
  <br>
  <em>Menu bar icon: idle (left) and recording (right)</em>
</p>

<p align="center">
  <img src="docs/screenshots/settings-general.png" alt="Settings - General" width="400">
  &nbsp;&nbsp;
  <img src="docs/screenshots/settings-models.png" alt="Settings - Models" width="400">
  <br>
  <em>Settings: General tab (left) and Models tab with resource monitoring (right)</em>
</p>

<p align="center">
  <img src="docs/screenshots/settings-audio.png" alt="Settings - Audio" width="400">
  &nbsp;&nbsp;
  <img src="docs/screenshots/settings-about.png" alt="Settings - About" width="400">
  <br>
  <em>Settings: Audio tab (left) and About tab (right)</em>
</p>

<p align="center">
  <img src="docs/screenshots/cursor-indicator.png" alt="Cursor Indicator" width="400">
  <br>
  <em>Floating mic indicator near text cursor during recording</em>
</p>

---

## ✨ Features

- **🔒 100% Local** - All audio processing happens on your machine. No internet required (except for one-time model downloads).
- **⌨️ System-Wide Text Injection** - Transcribed text is typed wherever your cursor is: browsers, Slack, VS Code, spreadsheets, terminals - everywhere.
- **🎯 Push-to-Talk** - Hold a hotkey (default: Right Option) to record. Release to transcribe.
- **👆 Double-Tap Toggle** - Double-tap the hotkey to start/stop recording.
- **🧠 Smart Model Selection** - Auto-detects your hardware (Apple Silicon/Intel, RAM) and recommends the best whisper model via WhisperKit.
- **⚡ Native Apple Acceleration** - CoreML + Metal + Neural Engine acceleration on Apple Silicon. No manual setup.
- **📊 Visual Feedback** - Menu bar icon changes color during recording and processing. Audio level indicator shows input.
- **⚙️ Configurable** - Choose hotkeys, models, languages, silence detection thresholds, and more.

---

## 🏛️ Why WhisperKit?

VocaMac uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) instead of raw whisper.cpp because:

| | WhisperKit | whisper.cpp |
|---|-----------|-------------|
| **Language** | Pure Swift (native) | C++ (requires bridging) |
| **Apple Silicon** | CoreML + Neural Engine | Metal only |
| **SPM Integration** | One-line dependency | Complex vendoring |
| **Model Format** | CoreML (optimized per device) | GGML (generic) |
| **Streaming** | First-class async/await | Manual threading |
| **Quality** | Same OpenAI Whisper models | Same OpenAI Whisper models |
| **Maintenance** | Argmax Inc. (commercial) | Community |

Same accuracy, dramatically better Apple platform integration.

---

## 📋 Requirements

- **macOS 13 (Ventura)** or later
- **Apple Silicon** (M1/M2/M3/M4)
- **Xcode 15+** or Swift 5.9+ (only for building from source)

### Permissions

VocaMac requires three macOS permissions:

| Permission | Why |
|---|---|
| **Microphone** | Capture your voice for transcription |
| **Accessibility** | Global hotkeys and text injection into apps |
| **Input Monitoring** | Detect hotkey presses system-wide |

> **Note:** After granting Input Monitoring, a restart of VocaMac is required for it to take effect.

---

## 🚀 Quick Start

### Option 1: Download DMG (Recommended)

1. **Download** the latest `VocaMac-x.x.x-arm64.dmg` from the [Releases page](https://github.com/jatinkrmalik/vocamac/releases)
2. **Open** the DMG and drag VocaMac to Applications
3. **Remove quarantine** (required because VocaMac is not yet notarized with Apple):
   ```bash
   xattr -cr /Applications/VocaMac.app
   ```
4. **Open** VocaMac from Applications (right-click → Open on first launch)
5. **Grant permissions** — Microphone, Accessibility, and Input Monitoring when prompted

### Option 2: Build from Source (Recommended)

```bash
git clone https://github.com/jatinkrmalik/vocamac.git
cd vocamac
make install
```

This builds VocaMac, installs it to `/Applications`, and launches it. Permissions are granted directly to VocaMac — just like the DMG method.

### Option 3: CLI Commands (For Developers)

```bash
git clone https://github.com/jatinkrmalik/vocamac.git
cd vocamac
make install-cli
```

This installs two commands to `~/.local/bin`:
- `vocamac &` — Launch VocaMac in background
- `vocamac-build` — Rebuild from source after pulling updates

> **Permissions note:** In CLI mode, macOS assigns permissions to your **terminal app** (Terminal, iTerm2, etc.) rather than VocaMac itself. Grant Microphone, Accessibility, and Input Monitoring to your terminal app instead.

### First Launch

1. **VocaMac appears in your menu bar** (microphone icon, no Dock icon)
2. **Grant permissions** — Microphone, Accessibility, and Input Monitoring (see [Permissions](#permissions) above)
3. **First model download** — WhisperKit automatically downloads the recommended model for your device (~40–500 MB depending on hardware)
4. **Start dictating** — Hold the **Right Option** key, speak, and release. Your words appear at the cursor!

---

## 🎮 Usage

### Push-to-Talk (Default)

| Action | What Happens |
|--------|-------------|
| **Hold Right Option** | Recording starts (menu bar icon turns red) |
| **Speak** | Audio is captured locally |
| **Release Right Option** | Recording stops → transcription → text injected at cursor |

### Double-Tap Toggle

| Action | What Happens |
|--------|-------------|
| **Double-tap Right Option** | Recording starts |
| **Speak** | Audio is captured |
| **Double-tap Right Option again** | Recording stops → transcription → text injection |

Switch between modes in **Settings → General → Activation**.

---

## 🧠 Whisper Models

VocaMac uses OpenAI Whisper models via WhisperKit's CoreML format. The app auto-detects your hardware and recommends the best model:

| Model | Parameters | Size | Speed | Quality | Best For |
|-------|-----------|------|-------|---------|----------|
| **Tiny** | 39M | ~0.4 GB | ⚡⚡⚡⚡⚡ | Good | Quick notes, older Macs |
| **Base** | 74M | ~0.8 GB | ⚡⚡⚡⚡ | Better | Daily use on 8GB Macs |
| **Small** | 244M | ~1.5 GB | ⚡⚡⚡ | Great | 16GB+ Apple Silicon |
| **Medium** | 769M | ~2.5 GB | ⚡⚡ | Excellent | 24GB+ for high accuracy |
| **Large v3** | 1550M | ~4.8 GB | ⚡ | Best | Maximum accuracy |

Models are downloaded automatically from [HuggingFace](https://huggingface.co/argmaxinc/whisperkit-coreml) on first use and cached locally. Download additional models from **Settings → Models**.

---

## ⚙️ Configuration

Open Settings from the menu bar popover or with **⌘,**

### General
- **Activation mode** - Push-to-Talk or Double-Tap Toggle
- **Hotkey** - Choose from Right Option, Right Command, Fn, function keys, etc.
- **Language** - Auto-detect or specify (English, Spanish, French, German, Chinese, Japanese, and more)
- **Launch at login**

### Audio
- **Max recording duration** - 30s, 60s, 120s, or 300s
- **Silence detection** - Auto-stop recording after configurable silence
- **Sound effects** - Toggle audio feedback for recording start/stop
- **Input device** - Select which microphone to use

### Models
- View system info and WhisperKit's hardware recommendation
- Download, load, and switch between models
- See which models are supported on your device

---

## 🏗️ Architecture

VocaMac is built with a clean, modular architecture using native Swift and SwiftUI:

```
VocaMacApp (SwiftUI MenuBarExtra)
├── AppState          - Central observable state
├── HotKeyManager     - CGEventTap global hotkey listener
├── AudioEngine       - AVAudioEngine mic capture (16kHz, mono, Float32)
├── WhisperService    - WhisperKit async transcription wrapper
│   └── ModelManager  - Model download, storage, device recommendations
│       └── SystemInfo - Hardware detection & model recommendation
├── SoundManager      - Audio feedback (start/stop recording cues)
├── TextInjector      - Clipboard + Cmd+V text injection
├── MenuBarView       - Status popover UI
└── SettingsView      - Configuration tabs (General, Models, Audio, About)
```

For detailed documentation, see:
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) - Technical Architecture
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) - Data Model & Entity Relationships

---

## 🔧 Development

### Prerequisites

- **Xcode 15+** or Swift 5.9+ toolchain
- **macOS 13+**

### Project Structure

```
VocaMac/
├── Package.swift                   # SPM config (WhisperKit dependency)
├── Sources/
│   └── VocaMac/
│       ├── App/
│       │   └── VocaMacApp.swift    # Entry point, MenuBarExtra
│       ├── Views/
│       │   ├── MenuBarView.swift   # Menu bar popover
│       │   └── SettingsView.swift  # Settings window (4 tabs)
│       ├── Services/
│       │   ├── AudioEngine.swift   # AVAudioEngine mic capture
│       │   ├── HotKeyManager.swift # CGEventTap global hotkeys
│       │   ├── WhisperService.swift# WhisperKit transcription wrapper
│       │   ├── ModelManager.swift  # Model download & management
│       │   ├── SoundManager.swift  # Audio feedback for recording
│       │   ├── TextInjector.swift  # Clipboard-based text injection
│       │   └── SystemInfo.swift    # Hardware detection
│       ├── Models/
│       │   ├── AppState.swift      # Central observable state
│       │   ├── TranscriptionResult.swift  # VocaTranscription type
│       │   └── WhisperModel.swift  # ModelSize enum, WhisperModelInfo
│       └── Resources/
├── Tests/
│   └── VocaMacTests/
├── Makefile                        # make build, install, test, clean
├── scripts/
│   ├── build.sh                    # Build .app bundle (dev)
│   ├── install.sh                  # Install to /Applications or CLI
│   └── uninstall.sh                # Full uninstall & cleanup
├── web/                            # Marketing website (vocamac.com)
├── docs/
│   ├── ARCHITECTURE.md             # Technical Architecture
│   └── DATA_MODEL.md               # Data Model & Entity Relationships
├── LICENSE                         # AGPL-3.0 License
└── .gitignore
```

### Build Commands

```bash
make install        # Build + install to /Applications (recommended)
make install-cli    # Install CLI commands to ~/.local/bin
make build          # Build .app bundle in repo root (dev iteration)
make test           # Run tests
make run            # Launch the locally built .app
make clean          # Remove build artifacts
make help           # Show all commands
```

### Uninstall

To completely remove VocaMac and all its data (downloaded models, preferences, caches):

```bash
./scripts/uninstall.sh
```

Use `--keep-build` to preserve build artifacts:

```bash
./scripts/uninstall.sh --keep-build
```

---


## 🌐 Cross-Platform

VocaMac is the macOS member of the Voca family:

| Platform | Project | Status |
|----------|---------|--------|
|  Linux | [VocaLinux](https://github.com/jatinkrmalik/vocalinux) | ✅ Available |
|  macOS | [VocaMac](https://github.com/jatinkrmalik/vocamac) | 🚧 Alpha |
| 🪟 Windows | [VocaWin](https://vocawin.com) | 📋 Planned |

Each platform uses native technologies for the best possible integration, while sharing the same UX patterns and Whisper model family.

---

## 🤝 Related Projects

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift native on-device speech recognition
- [VocaLinux](https://github.com/jatinkrmalik/vocalinux) - Voice-to-text for Linux
- [OpenAI Whisper](https://github.com/openai/whisper) - Original Whisper model

---

## ⚠️ Known Limitations

- **Ad-hoc code signing** - Accessibility and Input Monitoring permissions reset on every rebuild. Re-grant them after each build.
- **First launch requires internet** - WhisperKit downloads the speech recognition model on first run. All subsequent launches work fully offline.
- **macOS only** - Requires macOS 13 (Ventura) or later.

---

## 📄 License

AGPL-3.0 License - see [LICENSE](LICENSE) for details.

---

<div align="center">
  
Made with ❤️ for the macOS community!

</div>
