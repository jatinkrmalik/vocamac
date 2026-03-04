// AppState.swift
// VocaMac
//
// Central observable state for the entire application.
// All UI and services react to changes in AppState.

import Foundation
import SwiftUI
import Combine

// MARK: - Enums

/// Application status representing the current state of the transcription pipeline
enum AppStatus: String {
    case idle          // Ready for input, not recording
    case recording     // Actively capturing microphone audio
    case processing    // Transcribing audio via WhisperKit
    case error         // Something went wrong
}

/// How recording is activated by the user
enum ActivationMode: String, CaseIterable, Codable, Identifiable {
    case pushToTalk       // Hold key to record, release to stop
    case doubleTapToggle  // Double-tap key to start/stop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushToTalk:      return "Push to Talk (Hold)"
        case .doubleTapToggle: return "Double-Tap Toggle"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk:
            return "Hold the hotkey to record. Release to stop and transcribe."
        case .doubleTapToggle:
            return "Double-tap the hotkey to start recording. Double-tap again to stop."
        }
    }
}

/// Permission status for system permissions
enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    /// Current application status
    @Published var appStatus: AppStatus = .idle

    /// Whether the app is actively recording audio
    @Published var isRecording: Bool = false

    /// Current audio input level (0.0 - 1.0) for visual feedback
    @Published var audioLevel: Float = 0.0

    /// The most recent transcription result
    @Published var lastTranscription: VocaTranscription?

    /// Error message to display, if any
    @Published var errorMessage: String?

    /// Currently loaded/active whisper model info
    @Published var currentModel: WhisperModelInfo?

    /// All available models and their statuses
    @Published var availableModels: [WhisperModelInfo] = []

    /// Microphone permission status
    @Published var micPermission: PermissionStatus = .notDetermined

    /// Accessibility permission status
    @Published var accessibilityPermission: PermissionStatus = .notDetermined

    /// Detected system capabilities
    @Published var systemCapabilities: SystemCapabilities?

    /// WhisperKit's recommended model for this device
    @Published var deviceRecommendedModel: String?

    // MARK: - User Settings (persisted via UserDefaults)

    @AppStorage("vocamac.activationMode") var activationMode: ActivationMode = .pushToTalk
    @AppStorage("vocamac.hotKeyCode") var hotKeyCode: Int = 61  // Right Option
    @AppStorage("vocamac.doubleTapThreshold") var doubleTapThreshold: Double = 0.4
    @AppStorage("vocamac.silenceThreshold") var silenceThreshold: Double = 0.01
    @AppStorage("vocamac.silenceDuration") var silenceDuration: Double = 2.0
    @AppStorage("vocamac.maxRecordingDuration") var maxRecordingDuration: Int = 60
    @AppStorage("vocamac.selectedModelSize") var selectedModelSize: String = ModelSize.tiny.rawValue
    @AppStorage("vocamac.selectedLanguage") var selectedLanguage: String = "auto"
    @AppStorage("vocamac.launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("vocamac.preserveClipboard") var preserveClipboard: Bool = true

    // MARK: - Services

    let audioEngine = AudioEngine()
    let whisperService = WhisperService()
    let textInjector = TextInjector()
    let hotKeyManager = HotKeyManager()
    let modelManager = ModelManager()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        NSLog("[AppState] Initializing...")
        setupServices()
        // Trigger startup automatically
        Task {
            await performStartup()
        }
    }

    // MARK: - Setup

    private func setupServices() {
        // Detect system capabilities
        systemCapabilities = SystemInfo.detect()

        // Get WhisperKit's device recommendation
        let recommendation = modelManager.deviceRecommendation()
        deviceRecommendedModel = recommendation.defaultModel

        // Initialize available models list
        availableModels = ModelSize.allCases.map { size in
            WhisperModelInfo(
                size: size,
                filePath: modelManager.modelFolder(for: size),
                isDownloaded: modelManager.isModelDownloaded(size),
                isActive: size.rawValue == selectedModelSize,
                isSupported: modelManager.isModelSupported(size)
            )
        }

        // Setup audio level reporting
        audioEngine.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        // Setup silence detection callback
        audioEngine.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.activationMode == .doubleTapToggle && self.isRecording {
                    await self.stopRecordingAndTranscribe()
                }
            }
        }

        // Setup hotkey callbacks
        hotKeyManager.onRecordingStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }

        hotKeyManager.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        // Check permissions
        checkPermissions()
    }

    // MARK: - Permission Handling

    func checkPermissions() {
        // Check microphone permission
        audioEngine.checkPermission { [weak self] granted in
            Task { @MainActor in
                self?.micPermission = granted ? .granted : .denied
            }
        }

        // Check accessibility permission
        let accessibilityGranted = HotKeyManager.checkAccessibilityPermission(prompt: false)
        accessibilityPermission = accessibilityGranted ? .granted : .denied
    }

    func requestMicrophonePermission() {
        audioEngine.requestPermission { [weak self] granted in
            Task { @MainActor in
                self?.micPermission = granted ? .granted : .denied
            }
        }
    }

    func requestAccessibilityPermission() {
        let _ = HotKeyManager.checkAccessibilityPermission(prompt: true)
        // User must manually enable in System Settings; re-check after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    // MARK: - Recording Flow

    func startRecording() async {
        guard appStatus == .idle else { return }
        guard micPermission == .granted else {
            errorMessage = "Microphone permission is required. Please grant access in System Settings."
            appStatus = .error
            return
        }

        appStatus = .recording
        isRecording = true
        errorMessage = nil

        audioEngine.startRecording(
            silenceThreshold: Float(silenceThreshold),
            silenceDuration: silenceDuration,
            maxDuration: TimeInterval(maxRecordingDuration)
        )
    }

    func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        let audioData = audioEngine.stopRecording()
        isRecording = false
        audioLevel = 0.0

        guard !audioData.isEmpty else {
            appStatus = .idle
            return
        }

        appStatus = .processing

        do {
            let language = selectedLanguage == "auto" ? nil : selectedLanguage
            let result = try await whisperService.transcribe(
                audioData: audioData,
                language: language
            )

            lastTranscription = result

            // Inject text at cursor position
            if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textInjector.inject(
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    preserveClipboard: preserveClipboard
                )
            }

            appStatus = .idle
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            appStatus = .error

            // Auto-recover after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if self?.appStatus == .error {
                    self?.appStatus = .idle
                    self?.errorMessage = nil
                }
            }
        }
    }

    // MARK: - Model Management

    func loadModel(_ size: ModelSize? = nil) async {
        let modelName: String?
        if let size = size {
            modelName = modelManager.whisperKitModelName(for: size)
        } else {
            modelName = nil  // Let WhisperKit auto-select
        }

        do {
            // If model is downloaded locally, use the local folder
            let folder = size.flatMap { modelManager.modelFolder(for: $0) }
            try await whisperService.loadModel(name: modelName, folder: folder)

            if let size = size {
                selectedModelSize = size.rawValue
            }

            // Update model states
            let loadedName = whisperService.loadedModelName ?? ""
            for i in availableModels.indices {
                let matches = size != nil
                    ? availableModels[i].size == size
                    : loadedName.contains(availableModels[i].size.rawValue)
                availableModels[i].isActive = matches
                if matches {
                    currentModel = availableModels[i]
                }
            }
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    func downloadModel(_ size: ModelSize) async {
        guard let index = availableModels.firstIndex(where: { $0.size == size }) else { return }

        availableModels[index].downloadProgress = 0.0

        do {
            try await modelManager.downloadModel(size: size) { [weak self] progress in
                Task { @MainActor in
                    if let idx = self?.availableModels.firstIndex(where: { $0.size == size }) {
                        self?.availableModels[idx].downloadProgress = progress
                    }
                }
            }

            availableModels[index].isDownloaded = true
            availableModels[index].downloadProgress = nil
            availableModels[index].filePath = modelManager.modelFolder(for: size)
        } catch {
            availableModels[index].downloadProgress = nil
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Startup

    func performStartup() async {
        NSLog("[AppState] performStartup beginning...")

        // 1. Detect hardware
        systemCapabilities = SystemInfo.detect()
        NSLog("[AppState] System: %@ | %d GB RAM | %d cores",
              systemCapabilities?.processorName ?? "unknown",
              systemCapabilities?.physicalMemoryGB ?? 0,
              systemCapabilities?.coreCount ?? 0)

        // 2. Check/request permissions
        checkPermissions()
        NSLog("[AppState] Mic permission: %@ | Accessibility: %@",
              micPermission.rawValue, accessibilityPermission.rawValue)

        // 3. Load model — let WhisperKit auto-select and download the best model
        NSLog("[AppState] Loading WhisperKit model (auto-select)...")
        await loadModel()
        NSLog("[AppState] Model loaded: %@", whisperService.loadedModelName ?? "none")

        // 4. Always attempt to start hotkey listener
        // The event tap creation itself will fail if permissions aren't granted,
        // and we handle that gracefully in HotKeyManager.
        NSLog("[AppState] Attempting to start hotkey listener...")
        hotKeyManager.startListening(
            keyCode: hotKeyCode,
            mode: activationMode,
            doubleTapThreshold: doubleTapThreshold
        )
        if hotKeyManager.isListening {
            NSLog("[AppState] Hotkey listener active (keyCode=%d, mode=%@)", hotKeyCode, activationMode.rawValue)
        } else {
            NSLog("[AppState] WARNING: Hotkey listener failed to start. Check Accessibility & Input Monitoring permissions.")
        }

        NSLog("[AppState] Startup complete!")
    }
}
