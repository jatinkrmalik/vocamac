# VocaMac — Product Requirements Document (PRD)

**Version:** 1.0
**Date:** 2026-03-04
**Author:** Jatin Kumar Malik
**Status:** Draft

---

## 1. Executive Summary

VocaMac is a native macOS menu bar application that provides fast, accurate, and fully local voice-to-text transcription. Built on top of [whisper.cpp](https://github.com/ggerganov/whisper.cpp), it allows users to dictate text into any application — browsers, spreadsheets, messaging apps, IDEs, and more — without sending audio data to the cloud.

VocaMac is the macOS sibling of [VocaLinux](https://github.com/jatinkrmalik/vocalinux), which provides the same experience on Linux. A Windows counterpart (VocaWin) is planned for the future.

**Website:** [vocamac.com](https://vocamac.com)

---

## 2. Problem Statement

macOS users who want local, privacy-preserving voice dictation face several challenges:

1. **Apple's built-in dictation** requires an internet connection for most languages and offers limited customization
2. **Third-party solutions** (e.g., superwhisper) are closed-source and often require paid subscriptions
3. **Setting up whisper.cpp manually** requires command-line expertise and doesn't integrate with the system
4. **No seamless text injection** — most tools require copy-pasting from a separate window

VocaMac solves this by wrapping whisper.cpp in a polished, zero-configuration menu bar app that works everywhere your cursor is.

---

## 3. Target Users

| Persona | Description | Key Need |
|---------|-------------|----------|
| **Privacy-Conscious Professional** | Developer, writer, or knowledge worker who doesn't want audio sent to the cloud | Local-only processing, no telemetry |
| **Accessibility User** | Person with RSI, mobility challenges, or preference for voice input | Reliable, low-latency dictation across all apps |
| **Power User** | Someone who wants to augment their keyboard workflow with voice | Configurable hotkeys, fast toggle, works in any context |
| **Open-Source Enthusiast** | User who prefers transparent, community-driven tools | Open source, no vendor lock-in |

---

## 4. Goals & Success Metrics

### 4.1 MVP Goals
- Deliver a functional macOS menu bar app that transcribes speech to text locally
- Support push-to-talk and double-tap-to-toggle activation modes
- Inject transcribed text into any application at the cursor position
- Auto-detect system hardware and recommend an appropriate whisper model
- Ship with the `tiny` model (~39MB) for immediate out-of-box usage

### 4.2 Success Metrics
| Metric | Target |
|--------|--------|
| Time from hotkey press to recording start | < 100ms |
| Transcription latency (tiny model, 10s audio) | < 3s on Apple Silicon |
| Text injection success rate across common apps | > 95% |
| Cold start time (app launch to ready) | < 2s |
| Memory usage (idle, tiny model loaded) | < 150MB |

---

## 5. Features

### 5.1 MVP Features (P0 — Must Have)

#### F1: Menu Bar Presence
- App lives in the macOS menu bar with a microphone icon
- No Dock icon (LSUIElement = true)
- Icon states: idle (outline mic), recording (filled red mic), processing (animated spinner)
- Click to open a popover with status, quick actions, and settings access

#### F2: Voice Recording
- Real-time microphone capture using AVAudioEngine
- Audio format: 16kHz, mono, Float32 PCM (whisper.cpp native format)
- Visual audio level indicator during recording
- Automatic silence detection to stop recording after configurable silence duration (default: 2s)
- Maximum recording duration cap (default: 60s)

#### F3: Push-to-Talk Mode
- Hold a configurable hotkey (default: Right Option key) to record
- Recording starts on key down, stops on key release
- Transcription begins immediately on key release
- Works system-wide regardless of focused application

#### F4: Double-Tap Toggle Mode
- Double-tap a configurable hotkey (default: Right Option key) to start/stop recording
- Configurable double-tap interval threshold (default: 400ms)
- Visual feedback on toggle state change
- Works system-wide regardless of focused application

#### F5: Local Transcription via whisper.cpp
- Integrate whisper.cpp for local speech-to-text
- Metal acceleration on Apple Silicon for hardware-accelerated inference
- Support for all whisper model sizes (tiny, base, small, medium, large)
- Language auto-detection with option to specify language

#### F6: System-Wide Text Injection
- Transcribed text is injected at the current cursor position in any application
- Implementation via clipboard (NSPasteboard) + simulated Cmd+V keystroke
- Preserve and restore the user's clipboard content after injection
- Works in: browsers, text editors, IDEs, Slack, messaging apps, spreadsheets, terminal, etc.

#### F7: Hardware Detection & Model Recommendation
- Detect CPU architecture (Apple Silicon vs Intel)
- Detect available RAM
- Recommend the largest model the system can comfortably run
- Always default to `tiny` model for first-time users
- Show system info in settings for transparency

#### F8: Model Management
- Bundle `tiny` model (~39MB) with the app for zero-config first run
- Download larger models on demand from Hugging Face
- Show download progress with cancel option
- Verify downloaded model checksums
- Store models in `~/Library/Application Support/VocaMac/models/`

#### F9: Settings
- Hotkey configuration (key selection for push-to-talk / toggle)
- Activation mode selection (push-to-talk vs double-tap toggle)
- Model selection with system recommendation indicator
- Language preference (auto-detect or specific language)
- Silence detection threshold and duration
- Launch at login toggle
- Audio input device selection

#### F10: Permission Handling
- Graceful microphone permission request with explanation
- Accessibility permission guidance (required for CGEventTap global hotkeys)
- Step-by-step onboarding flow for first-time setup
- Status indicators showing which permissions are granted/missing

### 5.2 Post-MVP Features (P1 — Nice to Have)

#### F11: Transcription History
- Keep a local history of recent transcriptions
- Quick access to copy previous transcriptions
- Search through transcription history

#### F12: Custom Vocabulary / Prompt
- Allow users to provide a custom initial prompt to whisper for domain-specific vocabulary
- Useful for technical jargon, names, etc.

#### F13: Audio Feedback
- Optional subtle sound effects for recording start/stop
- Configurable or silent mode

#### F14: Multi-Language Support
- UI localization
- Per-transcription language selection

#### F15: Keyboard Shortcut for Settings
- Global shortcut to open settings window

### 5.3 Future Features (P2 — Roadmap)

#### F16: CoreML Optimized Models
- Support for CoreML-converted whisper models for even faster inference on Apple Silicon

#### F17: Real-Time Streaming Transcription
- Show transcription in real-time as the user speaks (partial results)

#### F18: VocaWin (Windows Port)
- Separate Windows application sharing the whisper.cpp core
- Native Windows UI using WinUI 3 or Tauri

#### F19: Auto-Update
- In-app update mechanism via Sparkle framework

#### F20: Plugin System
- Post-processing plugins (e.g., auto-punctuation, formatting, translation)

---

## 6. User Flows

### 6.1 First Launch
```
App launches → Menu bar icon appears
  → Check microphone permission
    → If not granted: Show permission dialog with instructions
    → If granted: Continue
  → Check accessibility permission
    → If not granted: Show guidance to enable in System Settings
    → If granted: Continue
  → Load bundled tiny model
  → Show welcome popover: "VocaMac is ready! Hold [Right Option] to dictate."
```

### 6.2 Push-to-Talk Flow
```
User holds Right Option key
  → Menu bar icon turns red (recording)
  → Audio capture begins
  → User speaks
  → User releases Right Option key
  → Menu bar icon shows spinner (processing)
  → whisper.cpp transcribes audio
  → Transcribed text injected at cursor position
  → Menu bar icon returns to idle
```

### 6.3 Double-Tap Toggle Flow
```
User double-taps Right Option key
  → Menu bar icon turns red (recording)
  → Audio capture begins
  → User speaks
  → User double-taps Right Option key again (or silence detected)
  → Menu bar icon shows spinner (processing)
  → whisper.cpp transcribes audio
  → Transcribed text injected at cursor position
  → Menu bar icon returns to idle
```

### 6.4 Model Download Flow
```
User opens Settings → Model Selection
  → Sees current model (tiny) and system recommendation
  → Selects larger model (e.g., "small")
  → Download begins with progress bar
  → User can cancel or continue using app during download
  → Download completes → Model verified
  → User switches to new model
```

---

## 7. Non-Functional Requirements

| Category | Requirement |
|----------|-------------|
| **Privacy** | All audio processing is local. No network calls except model downloads. No telemetry. |
| **Performance** | Transcription latency under 3s for 10s of audio on Apple Silicon with tiny model |
| **Compatibility** | macOS 13 (Ventura) and later. Universal binary (Apple Silicon + Intel) |
| **Resource Usage** | Idle memory < 50MB. Active (with tiny model) < 150MB |
| **Reliability** | Graceful handling of permission denials, model loading failures, audio device changes |
| **Accessibility** | VoiceOver compatible menu bar UI. High-contrast icon states |
| **Security** | No data leaves the machine. Models stored with standard file permissions. Code-signed app |

---

## 8. Technical Constraints

1. **CGEventTap requires Accessibility permission** — Users must manually grant this in System Settings
2. **Microphone access requires user consent** — Standard macOS permission dialog
3. **whisper.cpp model sizes** — Larger models provide better accuracy but need more RAM and take longer
4. **Clipboard-based text injection** — Temporarily overwrites clipboard; must restore afterward
5. **Menu bar space** — Icon should be compact; avoid text in menu bar, use icon states only

---

## 9. Out of Scope (MVP)

- Real-time streaming transcription (word-by-word display)
- Voice commands (e.g., "delete that", "new line")
- Speaker diarization
- Audio file transcription (file input)
- Cloud-based models or API calls
- Windows or Linux support (separate projects)
- App Store distribution (initial release via GitHub/DMG)

---

## 10. Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | Should we support configurable hotkey per mode (separate key for push-to-talk vs toggle)? | Open |
| 2 | Should the tiny model be bundled in the binary or downloaded on first launch? | Decided: Bundle it |
| 3 | What is the right default silence detection duration? | Tentative: 2 seconds |
| 4 | Should we support multiple audio input devices simultaneously? | Decided: Single device, selectable |
| 5 | License: MIT or GPLv3 (to match whisper.cpp's MIT license)? | Open |

---

## 11. Release Plan

| Milestone | Scope | Target |
|-----------|-------|--------|
| **v0.1.0 — MVP** | Core dictation flow: hotkey → record → transcribe → inject | Current sprint |
| **v0.2.0 — Polish** | Settings UI, model download, permission onboarding | Next sprint |
| **v0.3.0 — History** | Transcription history, custom prompts | Future |
| **v1.0.0 — Stable** | Auto-update, code signing, DMG distribution | Future |
