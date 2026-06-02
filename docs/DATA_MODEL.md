# VocaMac — Data Model & Entity Relationship Document

**Version:** 1.0
**Date:** 2026-03-04
**Author:** Jatin Kumar Malik
**Status:** Draft

---

## 1. Overview

VocaMac is a stateful desktop application with no database. All state is held in-memory during runtime, with user preferences persisted via `UserDefaults` and model files stored on disk. This document defines the core data entities, their relationships, and the storage strategy.

---

## 2. Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        AppState                                  │
│  (Central observable state — in memory)                         │
│                                                                  │
│  appStatus ──────────────► AppStatus (enum)                     │
│  activationMode ─────────► ActivationMode (enum)                │
│  isRecording: Bool                                               │
│  audioLevel: Float                                               │
│  lastTranscription ──────► TranscriptionResult?                 │
│  currentModel ───────────► WhisperModelInfo                     │
│  micPermission ──────────► PermissionStatus (enum)              │
│  accessibilityPermission ► PermissionStatus (enum)              │
│  selectedLanguage: String                                        │
│  selectedAudioDevice ───► AudioDevice?                          │
│  updateChecker ─────────► UpdateChecker                          │
└──────────┬──────────────────────────┬───────────────────────────┘
           │                          │
           ▼                          ▼
┌─────────────────────┐    ┌─────────────────────────────────┐
│ TranscriptionResult │    │       WhisperModelInfo          │
│                     │    │                                  │
│ id: UUID            │    │ size: ModelSize (enum)           │
│ text: String        │    │ filePath: URL                    │
│ duration: Double    │    │ isDownloaded: Bool               │
│ language: String    │    │ isActive: Bool                   │
│ timestamp: Date     │    │ downloadProgress: Double?        │
│ audioLengthSec: Int │    │ fileSize: Int64                  │
│ modelUsed: ModelSize│    │ checksum: String                 │
└─────────────────────┘    └──────────────┬──────────────────┘
                                          │
                                          ▼
                            ┌──────────────────────────────┐
                            │        ModelSize (enum)       │
                            │                               │
                            │ .tiny      (39 MB, ~1 GB RAM) │
                            │ .base      (142 MB, ~1.5 GB)  │
                            │ .small     (466 MB, ~2 GB)    │
                            │ .medium    (1.5 GB, ~5 GB)    │
                            │ .largeV3   (3.1 GB, ~10 GB)   │
                            └──────────────────────────────┘

┌─────────────────────────────┐    ┌─────────────────────────────┐
│     UserSettings            │    │      SystemCapabilities     │
│  (Persisted: UserDefaults)  │    │     (Detected at runtime)   │
│                             │    │                              │
│ activationMode: String      │    │ isAppleSilicon: Bool         │
│ hotKeyCode: Int             │    │ physicalMemoryGB: Int        │
│ doubleTapThreshold: Double  │    │ processorName: String        │
│ silenceThreshold: Float     │    │ coreCount: Int               │
│ silenceDuration: Double     │    │ recommendedModel: ModelSize  │
│ selectedModelSize: String   │    │ supportsMetalAccel: Bool     │
│ selectedLanguage: String    │    └─────────────────────────────┘
│ launchAtLogin: Bool         │
│ audioDeviceID: String?      │    ┌─────────────────────────────┐
│ maxRecordingDuration: Int   │    │      AudioDevice             │
│ preserveClipboard: Bool     │    │   (Detected at runtime)     │
└─────────────────────────────┘    │                              │
                                   │ id: String                   │
                                   │ name: String                 │
                                   │ isDefault: Bool              │
                                   │ sampleRate: Double           │
                                    │ channelCount: Int            │
                                    └─────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                       Update Checker Domain                      │
│                                                                  │
│  GitHubRelease                                                   │
│    - tagName: String                                             │
│    - name: String                                                │
│    - body: String                                                │
│    - htmlURL: URL                                                │
│    - assets: [GitHubAsset]                                       │
│                                                                  │
│  GitHubAsset                                                     │
│    - name: String                                                │
│    - browserDownloadURL: URL                                     │
│    - size: Int                                                   │
│    - digest: String?  // "sha256:..."                           │
│                                                                  │
│  UpdateInfo                                                      │
│    - version: String                                             │
│    - tagName: String                                             │
│    - releaseNotes: String                                        │
│    - releasePageURL: URL                                         │
│    - dmgURL: URL                                                 │
│    - dmgSize: Int                                                │
│    - sha256: String?                                             │
│                                                                  │
│  UpdateState (enum)                                              │
│    - idle | checking | upToDate                                  │
│    - updateAvailable(UpdateInfo)                                 │
│    - downloading(progress)                                        │
│    - readyToInstall(dmgPath)                                     │
│    - error(message)                                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Entity Definitions

### 3.1 `AppStatus` — Application State Machine

```
          ┌──────────────────────────────────────┐
          │                                      │
          ▼                                      │
     ┌─────────┐   hotkey    ┌───────────┐      │
     │  IDLE   │ ──pressed──►│ RECORDING │      │
     └─────────┘             └─────┬─────┘      │
          ▲                        │             │
          │                  hotkey released     │
          │                  or silence          │
          │                        │             │
          │                        ▼             │
          │                ┌──────────────┐      │
          │◄──completed────│  PROCESSING  │      │
          │                └──────┬───────┘      │
          │                       │              │
          │                  if error            │
          │                       │              │
          │                       ▼              │
          │                ┌──────────────┐      │
          └◄──dismissed────│    ERROR     │──────┘
                           └──────────────┘
```

```swift
enum AppStatus: String {
    case idle          // Ready for input, not recording
    case recording     // Actively capturing microphone audio
    case processing    // Transcribing audio via WhisperKit
    case error         // Something went wrong, showing error state
}
```

### 3.2 `ActivationMode` — How Recording is Triggered

```swift
enum ActivationMode: String, CaseIterable, Codable {
    case pushToTalk       // Hold key to record, release to stop
    case doubleTapToggle  // Double-tap key to start, double-tap again to stop
}
```

### 3.3 `PermissionStatus` — Permission State

```swift
enum PermissionStatus: String {
    case notDetermined  // Haven't asked yet
    case granted        // Permission granted
    case denied         // Permission denied by user
}
```

### 3.4 `ModelSize` — Whisper Model Variants

```swift
enum ModelSize: String, CaseIterable, Codable, Identifiable {
    case tiny     = "tiny"
    case base     = "base"
    case small    = "small"
    case medium   = "medium"
    case largeV3  = "large-v3"

    var id: String { rawValue }

    /// Display name for the UI
    var displayName: String {
        switch self {
        case .tiny:    return "Tiny (Fastest)"
        case .base:    return "Base"
        case .small:   return "Small"
        case .medium:  return "Medium"
        case .largeV3: return "Large v3 (Best Quality)"
        }
    }

    /// Model file name in CoreML format
    var fileName: String {
        "openai_whisper-\(rawValue)"
    }

    /// Approximate file size on disk
    var fileSizeBytes: Int64 {
        switch self {
        case .tiny:    return 39_000_000
        case .base:    return 142_000_000
        case .small:   return 466_000_000
        case .medium:  return 1_500_000_000
        case .largeV3: return 3_100_000_000
        }
    }

    /// Approximate RAM required for inference
    var ramRequiredGB: Double {
        switch self {
        case .tiny:    return 1.0
        case .base:    return 1.5
        case .small:   return 2.0
        case .medium:  return 5.0
        case .largeV3: return 10.0
        }
    }

    /// Download URL from Hugging Face
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/WhisperKit/resolve/main/\(fileName)")!
    }
}
```

### 3.5 `WhisperModelInfo` — Model Instance Metadata

```swift
struct WhisperModelInfo: Identifiable {
    let size: ModelSize
    var filePath: URL?
    var isDownloaded: Bool
    var isActive: Bool
    var downloadProgress: Double?  // 0.0 to 1.0 during download
    var checksum: String?

    var id: String { size.id }

    var statusDescription: String {
        if isActive { return "Active" }
        if isDownloaded { return "Downloaded" }
        if let progress = downloadProgress {
            return "Downloading (\(Int(progress * 100))%)"
        }
        return "Not Downloaded"
    }
}
```

### 3.6 `TranscriptionResult` — Output of a Transcription

```swift
struct TranscriptionResult: Identifiable {
    let id: UUID
    let text: String                // The transcribed text
    let duration: TimeInterval      // Time taken to transcribe
    let detectedLanguage: String    // ISO 639-1 language code
    let timestamp: Date             // When the transcription was performed
    let audioLengthSeconds: Double  // Length of the source audio
    let modelUsed: ModelSize        // Which model was used

    init(text: String, duration: TimeInterval, detectedLanguage: String,
         audioLengthSeconds: Double, modelUsed: ModelSize) {
        self.id = UUID()
        self.text = text
        self.duration = duration
        self.detectedLanguage = detectedLanguage
        self.timestamp = Date()
        self.audioLengthSeconds = audioLengthSeconds
        self.modelUsed = modelUsed
    }
}
```

### 3.7 `UserSettings` — Persisted User Preferences

```swift
struct UserSettings {
    // Activation
    var activationMode: ActivationMode = .pushToTalk
    var hotKeyCode: Int = 61                    // Right Option by default; selected key is reserved while running
    var doubleTapThreshold: Double = 0.4        // seconds

    // Audio
    var silenceThreshold: Float = 0.01          // RMS energy
    var silenceDuration: Double = 2.0           // seconds of silence to auto-stop
    var maxRecordingDuration: Int = 60          // seconds
    var selectedAudioDeviceID: String?          // nil = system default

    // Model
    var selectedModelSize: ModelSize = .tiny
    var selectedLanguage: String = "auto"       // "auto" or ISO 639-1 code

    // App Behavior
    var launchAtLogin: Bool = false
    var preserveClipboard: Bool = true          // Restore clipboard after text injection
    var playSoundEffects: Bool = false          // Sound on start/stop recording
}
```

**Storage:** Each property maps to a `UserDefaults` key with the prefix `vocamac.`:
```
vocamac.activationMode     = "pushToTalk"
vocamac.hotKeyCode         = 61
vocamac.doubleTapThreshold = 0.4
vocamac.silenceThreshold   = 0.01
...
```

### 3.8 `SystemCapabilities` — Hardware Detection Result

```swift
struct SystemCapabilities {
    let isAppleSilicon: Bool
    let physicalMemoryGB: Int
    let processorName: String
    let coreCount: Int
    let supportsMetalAcceleration: Bool
    let recommendedModel: ModelSize

    var summaryDescription: String {
        """
        Processor: \(processorName)
        Architecture: \(isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")
        Memory: \(physicalMemoryGB) GB
        Cores: \(coreCount)
        Metal: \(supportsMetalAcceleration ? "Supported" : "Not Available")
        Recommended Model: \(recommendedModel.displayName)
        """
    }
}
```

### 3.9 `AudioDevice` — Audio Input Device

```swift
struct AudioDevice: Identifiable, Hashable {
    let id: String              // Core Audio device UID
    let name: String            // Human-readable name
    let isDefault: Bool         // Is this the system default input?
    let sampleRate: Double      // Native sample rate
    let channelCount: Int       // Number of input channels
}
```

### 3.10 `GitHubRelease` — Latest Release API Payload

```swift
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool
    let publishedAt: String
    let assets: [GitHubAsset]
}
```

### 3.11 `GitHubAsset` — Release Asset Metadata

```swift
struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadURL: URL
    let contentType: String
    let digest: String?
}
```

### 3.12 `UpdateInfo` — Processed Update Candidate

```swift
struct UpdateInfo: Equatable {
    let version: String
    let tagName: String
    let releaseNotes: String
    let releasePageURL: URL
    let dmgURL: URL
    let dmgSize: Int
    let sha256: String?
}
```

### 3.13 `UpdateState` — Update UI/Service State

```swift
enum UpdateState: Equatable {
    case idle
    case checking
    case updateAvailable(UpdateInfo)
    case upToDate
    case downloading(progress: Double)
    case readyToInstall(dmgPath: URL)
    case error(String)
}
```

---

## 4. Persistence Strategy

| Data | Storage | Lifetime |
|------|---------|----------|
| User settings | `UserDefaults` | Permanent (until app uninstall or reset) |
| Model files | `~/Library/Application Support/VocaMac/models/` | Permanent (user can delete) |
| Audio buffers | In-memory `[Float]` | Discarded after transcription |
| Transcription results | In-memory (MVP) | Lost on app restart (MVP) |
| App state | In-memory `AppState` | Rebuilt on each launch |
| System capabilities | Computed at launch | Rebuilt on each launch |
| Update check cache | `UserDefaults` (`vocamac.update.*`) | Persisted across launches |

### 4.1 File System Layout

```
~/Library/Application Support/VocaMac/
├── models/
│   ├── openai_whisper-tiny          ← Always present (bundled or downloaded)
│   ├── openai_whisper-base          ← Optional (downloaded)
│   ├── openai_whisper-small         ← Optional (downloaded)
│   ├── openai_whisper-medium        ← Optional (downloaded)
│   └── openai_whisper-large-v3     ← Optional (downloaded)
└── logs/                      ← Future: debug logging
```

---

## 5. State Transitions

### 5.1 Recording State Machine

```
                    ┌─────────────┐
         ┌─────────│  App Launch  │──────────┐
         │         └─────────────┘           │
         ▼                                    ▼
  ┌──────────────┐                   ┌──────────────────┐
  │ Permissions  │                   │   Load Settings  │
  │   Check      │                   │   from Defaults  │
  └──────┬───────┘                   └────────┬─────────┘
         │                                     │
         ▼                                     ▼
  ┌──────────────┐                   ┌──────────────────┐
  │  Load Model  │◄──────────────────│  Detect Hardware │
  │  (tiny/def)  │                   │  & Recommend     │
  └──────┬───────┘                   └──────────────────┘
         │
         ▼
  ┌──────────────┐
  │    IDLE      │◄──────────────────────────────┐
  │   (Ready)    │                               │
  └──────┬───────┘                               │
         │ hotkey                                 │
         ▼                                       │
  ┌──────────────┐                               │
  │  RECORDING   │──── silence / hotkey ────┐    │
  │  (Capturing) │                          │    │
  └──────────────┘                          │    │
                                            ▼    │
                                     ┌───────────┴──┐
                                     │  PROCESSING  │
                                     │ (Transcribing│
                                     └──────┬───────┘
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │ TEXT INJECT  │
                                     │ (Paste text) │
                                     └──────┬───────┘
                                            │
                                            ▼
                                        Back to IDLE
```

### 5.2 Model State Machine

```
  ┌──────────────┐
  │ NOT_DOWNLOADED│
  └──────┬───────┘
         │ user requests download
         ▼
  ┌──────────────┐
  │ DOWNLOADING  │──── cancel ────► NOT_DOWNLOADED
  │ (progress %) │
  └──────┬───────┘
         │ download complete + checksum verified
         ▼
  ┌──────────────┐
  │  DOWNLOADED  │
  │  (on disk)   │
  └──────┬───────┘
         │ user selects as active model
         ▼
  ┌──────────────┐
  │   LOADING    │──── error ────► DOWNLOADED (retry)
  │ (into memory)│
  └──────┬───────┘
         │ loaded successfully
         ▼
  ┌──────────────┐
  │    ACTIVE    │
  │ (in use)     │
  └──────────────┘
```

---

## 6. Key Constants

```swift
enum VocaMacConstants {
    static let appSupportDirectory = "VocaMac"
    static let modelsSubdirectory = "models"
    static let userDefaultsPrefix = "vocamac."

    // Audio
    static let whisperSampleRate: Double = 16000.0
    static let audioBufferSize: UInt32 = 4096
    static let audioChannelCount: UInt32 = 1

    // Defaults
    static let defaultHotKeyCode: Int = 61          // Right Option
    static let defaultDoubleTapThreshold: Double = 0.4
    static let defaultSilenceThreshold: Float = 0.01
    static let defaultSilenceDuration: Double = 2.0
    static let defaultMaxRecordingDuration: Int = 60
    static let defaultModelSize: ModelSize = .tiny
    static let defaultLanguage: String = "auto"

    // Text Injection
    static let clipboardSettleDelay: UInt32 = 50_000   // 50ms in microseconds
    static let pasteEventDelay: UInt32 = 10_000         // 10ms between key events
    static let clipboardRestoreDelay: Double = 0.15     // 150ms before restoring clipboard

    // Model Download
    static let downloadTimeoutSeconds: TimeInterval = 300
    static let downloadRetryAttempts: Int = 3
}
```
