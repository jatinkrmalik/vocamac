# VocaMac — Technical Architecture Document

**Version:** 1.0
**Date:** 2026-03-04
**Author:** Jatin Kumar Malik
**Status:** Draft

---

## 1. System Overview

VocaMac is a native macOS menu bar application built with Swift and SwiftUI. It captures microphone audio, transcribes it locally using WhisperKit, and injects the resulting text at the cursor position in any application.

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     macOS System Layer                        │
│  ┌────────────┐  ┌──────────────┐  ┌───────────────────┐    │
│  │ CGEventTap │  │ AVAudioEngine│  │   NSPasteboard    │    │
│  │ (Hotkeys)  │  │ (Microphone) │  │ + CGEvent (Paste) │    │
│  └─────┬──────┘  └──────┬───────┘  └────────┬──────────┘    │
│        │                │                     │               │
├────────┼────────────────┼─────────────────────┼───────────────┤
│        │          VocaMac Application         │               │
│        ▼                ▼                     ▲               │
│  ┌───────────┐  ┌─────────────┐  ┌───────────────────┐      │
│  │ HotKey    │  │ Audio       │  │   TextInjector    │      │
│  │ Manager   │  │ Engine      │  │                   │      │
│  └─────┬─────┘  └──────┬──────┘  └────────▲──────────┘      │
│        │               │                   │                  │
│        ▼               ▼                   │                  │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   AppState                           │    │
│  │          (Observable, Reactive State)                │    │
│  └───────────────────────┬──────────────────────────────┘    │
│                          │                                    │
│                          ▼                                    │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              WhisperService                          │    │
│  │         (WhisperKit (CoreML))                   │    │
│  │     ┌──────────────────────────────┐                 │    │
│  │     │       ModelManager           │                 │    │
│  │     │  (Download, Load, Detect)    │                 │    │
│  │     └──────────────────────────────┘                 │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   SwiftUI Layer                       │    │
│  │  ┌──────────────┐  ┌────────────┐  ┌──────────────┐ │    │
│  │  │ MenuBarView  │  │SettingsView│  │SettingsView│ │    │
│  │  └──────────────┘  └────────────┘  └──────────────┘ │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Language | Swift | 5.9+ | Primary development language |
| UI | SwiftUI | macOS 13+ | Menu bar UI, settings, onboarding |
| Audio | AVAudioEngine | macOS 13+ | Real-time microphone capture |
| Hotkeys | CGEventTap (Quartz) | macOS 13+ | System-wide key event interception |
| Text Injection | NSPasteboard + CGEvent | macOS 13+ | Clipboard-based text insertion |
| STT Engine | WhisperKit | 0.9.4+ | CoreML-based on-device speech-to-text |
| Acceleration | Metal | macOS 13+ | GPU-accelerated inference on Apple Silicon |
| Build | Swift Package Manager | 5.9+ | Dependency management and build |
| Min OS | macOS 13 Ventura | — | Minimum supported macOS version |

---

## 3. Module Design

### 3.1 Module Dependency Graph

```
VocaMacApp (entry point)
    ├── AppState (shared state)
    │     ├── HotKeyManager
    │     ├── AudioEngine
    │     ├── WhisperService
    │     │     └── ModelManager
    │     │           └── SystemInfo
    │     └── TextInjector
    ├── MenuBarView
    ├── SettingsView
    └── SettingsView
```

### 3.2 Module Specifications

#### 3.2.1 `VocaMacApp` — Application Entry Point

**Responsibility:** Bootstrap the app, configure as menu bar-only (no Dock icon), initialize all services.

**Key Design Decisions:**
- Uses `MenuBarExtra` (SwiftUI, macOS 13+) for the menu bar presence
- Sets `LSUIElement = true` in Info.plist to hide from Dock
- Creates `AppState` as `@StateObject` and passes it through the environment

**Lifecycle:**
```
App Launch
  → Initialize AppState
  → AppState checks permissions
  → AppState loads default model
  → MenuBarExtra renders
  → HotKeyManager starts listening
  → App is ready
```

#### 3.2.2 `AppState` — Central State Management

**Responsibility:** Single source of truth for all app state. Observable object that drives reactive UI updates.

**Key State Properties:**
```swift
@Published var appStatus: AppStatus           // .idle, .recording, .processing, .error
@Published var currentModel: WhisperModelInfo // Currently loaded model
@Published var activationMode: ActivationMode // .pushToTalk, .doubleTapToggle
@Published var isRecording: Bool
@Published var audioLevel: Float              // 0.0 - 1.0, for visual feedback
@Published var lastTranscription: String?
@Published var micPermission: PermissionStatus
@Published var accessibilityPermission: PermissionStatus
@Published var selectedLanguage: String       // "auto" or ISO 639-1 code
```

**Orchestration Logic:**
```
HotKey Triggered (start)
  → Set appStatus = .recording
  → AudioEngine.startRecording()

HotKey Triggered (stop)
  → AudioEngine.stopRecording() → returns [Float]
  → Set appStatus = .processing
  → WhisperService.transcribe([Float]) → returns String
  → TextInjector.inject(String)
  → Set appStatus = .idle
```

#### 3.2.3 `HotKeyManager` — Global Hotkey Listener

**Responsibility:** Listen for system-wide key events to trigger recording start/stop.

**Implementation Approach:**
- Uses `CGEvent.tapCreate()` to create a Mach port event tap
- Tap is inserted at `.cghidEventTap` level for system-wide coverage
- Callback processes `keyDown` and `keyUp` events for the configured hotkey

**Activation Modes:**

| Mode | Trigger Start | Trigger Stop |
|------|--------------|--------------|
| Push-to-Talk | Key down | Key up |
| Double-Tap Toggle | 2nd tap within threshold | Next double-tap, or silence detection |

**Double-Tap Detection Algorithm:**
```
On keyDown:
  currentTime = now()
  if (currentTime - lastKeyDownTime) < doubleTapThreshold:
    → Fire "double tap" event
    → Reset lastKeyDownTime
  else:
    → Store lastKeyDownTime = currentTime

On keyUp:
  (Used only for push-to-talk mode)
```

**Default Hotkey:** Right Option (keyCode 61)

**Required Permission:** Accessibility (System Settings → Privacy & Security → Accessibility)

#### 3.2.4 `AudioEngine` — Microphone Capture

**Responsibility:** Capture audio from the microphone in the format required by WhisperKit.

**Audio Pipeline:**
```
Microphone → AVAudioInputNode → Format Converter → Buffer Accumulator
                                  (16kHz, mono,      ([Float] array)
                                   Float32 PCM)
```

**Key Configuration:**
- Sample rate: 16,000 Hz (WhisperKit requirement)
- Channels: 1 (mono)
- Format: Float32 PCM
- Buffer size: 4096 frames per callback

**Silence Detection:**
- Calculate RMS energy of each buffer
- Track time since last buffer above silence threshold
- Trigger silence callback when silence exceeds configured duration
- Configurable threshold (default: 0.01 RMS) and duration (default: 2.0s)

**Audio Level Reporting:**
- Normalize RMS energy to 0.0–1.0 range
- Report to AppState on each buffer for UI visualization
- Throttle updates to ~15 Hz to avoid excessive UI refreshes

#### 3.2.5 `WhisperService` — Speech-to-Text Engine

**Responsibility:** Load WhisperKit models and perform transcription.

**Integration Strategy:**
- WhisperKit source code is included as a git submodule or vendored dependency
- C bridging header (`whisper-bridge.h`) exposes WhisperKit's C API to Swift
- Swift wrapper class provides a clean async API

**Core API:**
```swift
class WhisperService {
    func loadModel(path: String) throws
    func transcribe(audioData: [Float], language: String?) async throws -> TranscriptionResult
    func unloadModel()
    var isModelLoaded: Bool { get }
}
```

**Transcription Flow:**
```
audioData: [Float]
  → whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
  → Configure params (language, threads, etc.)
  → whisper_full(ctx, params, audioData, count)
  → Iterate segments: whisper_full_get_segment_text()
  → Concatenate segments → TranscriptionResult
```

**Threading:**
- Transcription runs on a background thread (Swift async/await)
- Number of threads = min(processorCount, 4) for optimal performance
- Model loading also happens on background thread

**Metal Acceleration:**
- Enabled by default on Apple Silicon when WhisperKit is compiled with Metal support
- Compile flag: `WHISPER_METAL=1` or `CoreML_METAL=1`
- Falls back to CPU on Intel Macs

#### 3.2.6 `ModelManager` — Model Lifecycle Management

**Responsibility:** Discover, download, verify, and manage whisper model files.

**Model Storage:**
```
~/Library/Application Support/VocaMac/
  └── models/
      ├── ggml-tiny.bin        (39 MB)
      ├── ggml-base.bin        (142 MB)  ← downloaded on demand
      ├── ggml-small.bin       (466 MB)  ← downloaded on demand
      ├── ggml-medium.bin      (1.5 GB)  ← downloaded on demand
      └── ggml-large-v3.bin    (3.1 GB)  ← downloaded on demand
```

**Model Catalog:**
| Model | Size | RAM Required | Relative Speed | Accuracy |
|-------|------|-------------|----------------|----------|
| tiny | 39 MB | ~1 GB | 1x (fastest) | Good |
| base | 142 MB | ~1.5 GB | 2x | Better |
| small | 466 MB | ~2 GB | 4x | Great |
| medium | 1.5 GB | ~5 GB | 8x | Excellent |
| large-v3 | 3.1 GB | ~10 GB | 16x | Best |

**Download Source:** Hugging Face (`https://huggingface.co/ggerganov/WhisperKit/resolve/main/`)

**Download Process:**
1. Check if model file exists locally
2. If not, initiate async download with URLSession
3. Report progress via delegate/closure
4. Verify SHA256 checksum after download
5. Move to models directory on success

#### 3.2.7 `SystemInfo` — Hardware Detection

**Responsibility:** Detect system hardware capabilities and recommend optimal model size.

**Detection Points:**
- CPU architecture: `uname()` → arm64 (Apple Silicon) or x86_64 (Intel)
- Physical RAM: `ProcessInfo.processInfo.physicalMemory`
- Processor name: `sysctlbyname("machdep.cpu.brand_string")`
- Core count: `ProcessInfo.processInfo.activeProcessorCount`

**Recommendation Algorithm:**
```
Apple Silicon:
  RAM ≤ 8 GB  → tiny  (safe default)
  RAM = 16 GB → small (good balance)
  RAM ≥ 24 GB → medium (high quality)

Intel:
  RAM ≤ 8 GB  → tiny
  RAM = 16 GB → base
  RAM ≥ 32 GB → small
```

#### 3.2.8 `TextInjector` — System-Wide Text Insertion

**Responsibility:** Insert transcribed text at the cursor position in any application.

**Algorithm:**
```
1. Save current clipboard contents
2. Write transcribed text to clipboard (NSPasteboard)
3. Wait 50ms (ensure clipboard is updated)
4. Simulate Cmd+V keypress via CGEvent
5. Wait 100ms (ensure paste is processed)
6. Restore original clipboard contents
```

**CGEvent Simulation:**
```
CGEventSource(stateID: .hidSystemState)
  → Create keyDown for Cmd (keyCode 55)
  → Create keyDown for V (keyCode 9) with .maskCommand flag
  → Create keyUp for V
  → Create keyUp for Cmd
  → Post all events to .cghidEventTap
```

**Required Permission:** Accessibility (same as HotKeyManager)

**Edge Cases:**
- If clipboard contains non-text content (images, files), save and restore the full pasteboard items
- Add configurable delay between paste simulation events for slower apps
- Handle the case where the user's clipboard is empty

---

## 4. Data Flow

### 4.1 Complete Transcription Pipeline

```
User Action
  │
  ▼
HotKeyManager (CGEventTap)
  │ detects hotkey press/release
  ▼
AppState (orchestrator)
  │ sets status = .recording
  ▼
AudioEngine (AVAudioEngine)
  │ captures mic audio → [Float] buffer
  │ reports audio levels → AppState → MenuBarView
  ▼
AppState (orchestrator)
  │ sets status = .processing
  ▼
WhisperService (WhisperKit)
  │ transcribes [Float] → String
  ▼
AppState (orchestrator)
  │ sets status = .idle
  ▼
TextInjector (NSPasteboard + CGEvent)
  │ injects text at cursor
  ▼
Target Application (Safari, Slack, VS Code, etc.)
  │ receives pasted text
  ▼
Done
```

### 4.2 Data Formats at Each Stage

| Stage | Format | Details |
|-------|--------|---------|
| Microphone input | Hardware-dependent | Usually 44.1kHz or 48kHz, stereo |
| After format conversion | Float32 PCM | 16kHz, mono, [-1.0, 1.0] range |
| Audio buffer | `[Float]` | Swift array of samples |
| WhisperKit input | `const float *` | C pointer to samples array |
| WhisperKit output | `const char *` | C string per segment |
| Transcription result | `String` | Swift string, all segments concatenated |
| Clipboard | `NSPasteboard.string` | UTF-8 string |
| Key simulation | `CGEvent` | Keyboard events posted to HID |

---

## 5. Concurrency Model

```
Main Thread (UI)
  ├── SwiftUI rendering
  ├── AppState @Published updates
  └── Menu bar icon updates

Background Thread (Audio)
  └── AVAudioEngine tap callback
      └── Audio buffer accumulation

Background Thread (Transcription)
  └── whisper_full() call
      └── Can take 1-10+ seconds depending on model

Main Thread (Text Injection)
  └── NSPasteboard + CGEvent posting
      └── Must be on main thread for CGEvent
```

**Key Threading Rules:**
1. Audio capture callbacks run on AVAudioEngine's internal thread — keep work minimal
2. Transcription runs via `Task { }` on a background executor — never block the main thread
3. UI updates via `@MainActor` or `DispatchQueue.main`
4. CGEvent posting should happen from the main thread
5. Model loading/downloading uses async/await on background threads

---

## 6. Permission Model

| Permission | macOS API | Required For | How to Request |
|------------|-----------|-------------|----------------|
| Microphone | AVCaptureDevice.requestAccess | AudioEngine | Programmatic prompt |
| Accessibility | AXIsProcessTrusted | HotKeyManager, TextInjector | Manual: System Settings → Privacy → Accessibility |

**Accessibility Permission Check:**
```swift
let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
let isTrusted = AXIsProcessTrustedWithOptions(options)
```

Note: Unlike microphone access, Accessibility permission cannot be granted via a system dialog — the user must manually add the app in System Settings. The app should provide clear instructions.

---

## 7. Build & Distribution

### 7.1 Build Configuration

```
Package.swift
  ├── Platform: .macOS(.v13)
  ├── Products: VocaMac executable
  ├── Dependencies: WhisperKit (vendored or submodule)
  ├── Swift settings: -O (optimized for release)
  └── C settings: -DCoreML_METAL=1 (Metal acceleration)
```

### 7.2 Build Commands

```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release

# Run
swift run VocaMac

# Create app bundle (requires additional scripting)
./scripts/bundle.sh
```

### 7.3 Distribution Strategy (MVP)

1. **GitHub Releases** — DMG or ZIP containing the .app bundle
2. **Homebrew Cask** — `brew install --cask vocamac` (post-MVP)
3. **Mac App Store** — Future consideration (requires sandbox compliance)

---

## 8. Cross-Platform Strategy

### 8.1 Architecture for Future Portability

While VocaMac is a native macOS app, the architecture is designed to facilitate a future Windows port (VocaWin):

```
Shared (C/C++):
  └── WhisperKit           ← Already cross-platform
  └── Model format (CoreML)   ← Already cross-platform

Platform-Specific:
  ┌──────────────────────┬──────────────────────┐
  │      macOS            │      Windows         │
  ├──────────────────────┼──────────────────────┤
  │ Swift + SwiftUI      │ C++/C# + WinUI 3    │
  │ AVAudioEngine        │ WASAPI / NAudio      │
  │ CGEventTap           │ SetWindowsHookEx     │
  │ NSPasteboard + CGEvt │ Clipboard + SendInput│
  │ Metal acceleration   │ CUDA / DirectML      │
  │ MenuBarExtra         │ System Tray (NotifyIcon) │
  └──────────────────────┴──────────────────────┘
```

### 8.2 What Can Be Shared

- **WhisperKit** — The core engine is already cross-platform
- **Model files** — CoreML model format works on all platforms
- **Model catalog** — Same download URLs, checksums, metadata
- **UX patterns** — Same user flows and interaction design

### 8.3 What Must Be Platform-Specific

- UI framework and rendering
- Audio capture API
- Global hotkey mechanism
- Text injection method
- Permission handling
- App lifecycle and distribution

---

## 9. Error Handling Strategy

| Error Scenario | Handling |
|---------------|----------|
| Microphone permission denied | Show guidance to enable in System Settings |
| Accessibility permission denied | Show step-by-step guide with screenshots |
| Model file corrupted/missing | Re-download model, fall back to bundled tiny |
| Audio device disconnected | Detect and notify user, pause recording |
| Transcription fails | Show error in menu bar popover, log details |
| Clipboard restore fails | Log warning, don't crash — clipboard is transient |
| Out of memory during transcription | Suggest a smaller model, show clear error |
| Network error during model download | Retry with exponential backoff, allow manual retry |

---

## 10. Security Considerations

1. **No network communication** except model downloads from Hugging Face
2. **No telemetry or analytics** — fully offline operation
3. **Audio data never leaves the device** — processed entirely in-memory
4. **No persistent audio storage** — audio buffers are discarded after transcription
5. **Model files verified by checksum** — prevent tampering
6. **Code signing** — App should be signed with a Developer ID certificate
7. **Hardened runtime** — Enable for Gatekeeper compatibility
