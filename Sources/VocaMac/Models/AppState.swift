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

    /// Input Monitoring permission status
    @Published var inputMonitoringPermission: PermissionStatus = .notDetermined

    /// Detected system capabilities
    @Published var systemCapabilities: SystemCapabilities?

    /// WhisperKit's recommended model for this device
    @Published var deviceRecommendedModel: String?

    // MARK: - User Settings (persisted via UserDefaults)

    @AppStorage("vocamac.hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
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
    @AppStorage("vocamac.soundEffectsEnabled") var soundEffectsEnabled: Bool = true
    @AppStorage("vocamac.showCursorIndicator") var showCursorIndicator: Bool = true
    @AppStorage("vocamac.translationEnabled") var translationEnabled: Bool = false
    @AppStorage("vocamac.logLevel") var logLevel: String = "info"

    // MARK: - Services

    let audioEngine = AudioEngine()
    let whisperService = WhisperService()
    let textInjector = TextInjector()
    let hotKeyManager = HotKeyManager()
    let modelManager = ModelManager()
    let soundManager = SoundManager()
    let cursorOverlay = CursorOverlayManager()

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        VocaLogger.info(.appState, "Initializing...")
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
                self?.cursorOverlay.updateAudioLevel(level)
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
        // Check microphone permission (tri-state: notDetermined, granted, denied)
        micPermission = audioEngine.checkPermissionStatus()

        // Check accessibility permission
        let accessibilityGranted = HotKeyManager.checkAccessibilityPermission(prompt: false)
        accessibilityPermission = accessibilityGranted ? .granted : .denied

        // Check input monitoring permission
        // If we can successfully create an event tap (even briefly), Input Monitoring is granted.
        // CGPreflightListenEventAccess() is available on macOS 15+, so we use a tap test as fallback.
        let inputMonitoringGranted = checkInputMonitoringPermission()
        inputMonitoringPermission = inputMonitoringGranted ? .granted : .denied
    }

    /// Check Input Monitoring permission.
    /// Uses multiple strategies since no single approach is 100% reliable:
    /// 1. If HotKeyManager created a tap, check if macOS has disabled it (revocation)
    /// 2. If HotKeyManager failed to create a tap, permission is likely denied
    /// 3. Try creating a fresh .cghidEventTap (same type HotKeyManager uses)
    private func checkInputMonitoringPermission() -> Bool {
        // Strategy 1: If HotKeyManager has an active tap, check if macOS disabled it.
        // macOS disables existing taps when Input Monitoring is revoked.
        if hotKeyManager.isListening, let tap = hotKeyManager.activeEventTap {
            return CGEvent.tapIsEnabled(tap: tap)
        }

        // Strategy 2: Try creating a fresh .cghidEventTap — the same type
        // HotKeyManager uses. This is more accurate than .cgSessionEventTap
        // which may inherit Terminal's permissions when launched from CLI.
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    func requestMicrophonePermission() {
        if micPermission == .denied {
            // Already denied — re-requesting won't show the prompt again.
            // Open System Settings so the user can manually enable it.
            openMicrophoneSettings()
            return
        }

        // First time or notDetermined — trigger the system permission prompt
        audioEngine.requestPermission { [weak self] granted in
            Task { @MainActor in
                self?.micPermission = granted ? .granted : .denied
            }
        }
    }

    /// Open the Microphone privacy pane in System Settings
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        // Re-check after user has time to toggle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    func requestAccessibilityPermission() {
        let _ = HotKeyManager.checkAccessibilityPermission(prompt: true)
        // User must manually enable in System Settings; re-check after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    func requestInputMonitoringPermission() {
        // Attempting to create an event tap triggers macOS to auto-add
        // the app to the Input Monitoring list in System Settings.
        // Use .cghidEventTap (same as HotKeyManager) for consistent behavior.
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
        }

        // Open Input Monitoring settings pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }

        // Re-check after user has time to toggle
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

        // Show cursor indicator
        if showCursorIndicator {
            cursorOverlay.show()
        }

        // Play start sound and wait for completion before starting mic
        // This prevents the sound from being captured into the audio buffer
        if soundEffectsEnabled {
            await soundManager.playStartSoundAsync()
        }

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

        // Play stop sound
        if soundEffectsEnabled {
            soundManager.playStopSound()
        }

        // Transition cursor indicator to processing state (red -> purple)
        // Keeps the overlay visible so the user knows text is on its way
        cursorOverlay.transitionToProcessing()

        guard !audioData.isEmpty else {
            cursorOverlay.hide()
            appStatus = .idle
            return
        }

        appStatus = .processing

        do {
            let language = selectedLanguage == "auto" ? nil : selectedLanguage
            let result = try await whisperService.transcribe(
                audioData: audioData,
                language: language,
                translate: translationEnabled
            )

            lastTranscription = result

            // Inject text at cursor position
            if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textInjector.inject(
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    preserveClipboard: preserveClipboard
                )
            }

            cursorOverlay.hide()
            appStatus = .idle
        } catch {
            cursorOverlay.hide()
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

        // Mark the model as loading
        if let size = size, let idx = availableModels.firstIndex(where: { $0.size == size }) {
            availableModels[idx].isLoading = true
            availableModels[idx].loadingStatus = "Preparing…"
        }

        do {
            // If model is downloaded locally, use the local folder
            let folder = size.flatMap { modelManager.modelFolder(for: $0) }

            // Update status: unpacking
            if let size = size, let idx = availableModels.firstIndex(where: { $0.size == size }) {
                availableModels[idx].loadingStatus = "Unpacking model…"
            }

            // Load model with status callback
            try await whisperService.loadModel(name: modelName, folder: folder) { [weak self] phase in
                Task { @MainActor in
                    guard let self = self, let size = size,
                          let idx = self.availableModels.firstIndex(where: { $0.size == size }) else { return }
                    self.availableModels[idx].loadingStatus = phase
                }
            }

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
                availableModels[i].isLoading = false
                if matches {
                    currentModel = availableModels[i]
                }
            }
        } catch {
            // Clear loading state on error
            if let size = size, let idx = availableModels.firstIndex(where: { $0.size == size }) {
                availableModels[idx].isLoading = false
            }
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    func downloadModel(_ size: ModelSize) async {
        guard let index = availableModels.firstIndex(where: { $0.size == size }) else { return }

        availableModels[index].downloadProgress = 0.0

        do {
            try await modelManager.downloadModel(size: size) { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let idx = self.availableModels.firstIndex(where: { $0.size == size }) {
                        // Only update progress if we haven't already completed (1.0)
                        // This prevents race conditions with the simulated progress task
                        if progress >= 1.0 || self.availableModels[idx].downloadProgress != nil {
                            self.availableModels[idx].downloadProgress = progress
                        }
                    }
                }
            }

            // Small delay to let the final progress (1.0) callback settle on MainActor
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            // Refresh all model statuses to ensure previously downloaded models are preserved
            refreshModelStatuses()
        } catch {
            if let idx = availableModels.firstIndex(where: { $0.size == size }) {
                availableModels[idx].downloadProgress = nil
            }
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    /// Refresh the download status of all models
    /// This ensures that all previously downloaded models are detected and marked correctly
    private func refreshModelStatuses() {
        for i in availableModels.indices {
            let size = availableModels[i].size
            availableModels[i].isDownloaded = modelManager.isModelDownloaded(size)
            availableModels[i].downloadProgress = nil
            availableModels[i].filePath = modelManager.modelFolder(for: size)
        }
    }

    // MARK: - Startup

    func performStartup() async {
        VocaLogger.info(.appState, "performStartup beginning...")

        // 1. Detect hardware
        systemCapabilities = SystemInfo.detect()
        let sysInfo = systemCapabilities
        VocaLogger.info(.appState, "System: \(sysInfo?.processorName ?? "unknown") | \(sysInfo?.physicalMemoryGB ?? 0) GB RAM | \(sysInfo?.coreCount ?? 0) cores")

        // 2. Check/request permissions
        checkPermissions()
        VocaLogger.info(.appState, "Mic permission: \(micPermission.rawValue) | Accessibility: \(accessibilityPermission.rawValue) | Input Monitoring: \(inputMonitoringPermission.rawValue)")

        // Auto-prompt for microphone permission on first launch
        if micPermission == .notDetermined {
            VocaLogger.info(.appState, "Mic permission not determined — requesting...")
            requestMicrophonePermission()
        }

        // 3. Load model — let WhisperKit auto-select and download the best model
        VocaLogger.info(.appState, "Loading WhisperKit model (auto-select)...")
        await loadModel()
        NSLog("[AppState] Model loaded: %@", whisperService.loadedModelName ?? "none")

        // 4. Always attempt to start hotkey listener
        // The event tap creation itself will fail if permissions aren't granted,
        // and we handle that gracefully in HotKeyManager.
        VocaLogger.info(.appState, "Attempting to start hotkey listener...")
        hotKeyManager.startListening(
            keyCode: hotKeyCode,
            mode: activationMode,
            doubleTapThreshold: doubleTapThreshold
        )
        if hotKeyManager.isListening {
            VocaLogger.info(.appState, "Hotkey listener active (keyCode=\(hotKeyCode), mode=\(activationMode.rawValue))")
        } else {
            VocaLogger.warning(.appState, "Hotkey listener failed to start. Check Accessibility & Input Monitoring permissions.")
        }

        VocaLogger.info(.appState, "Startup complete!")
    }
    func completeOnboarding() {
        hasCompletedOnboarding = true
        NSLog("[AppState] Onboarding completed!")
    }
}
