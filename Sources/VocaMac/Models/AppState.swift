// AppState.swift
// VocaMac
//
// Central observable state for the entire application.
// All UI and services react to changes in AppState.

import Foundation
import SwiftUI
import Combine
import ServiceManagement

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

    // Permissions are managed by PermissionManager.
    // These computed properties maintain backward compatibility for views.
    var micPermission: PermissionStatus { permissionManager.micPermission }
    var accessibilityPermission: PermissionStatus { permissionManager.accessibilityPermission }
    var inputMonitoringPermission: PermissionStatus { permissionManager.inputMonitoringPermission }

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

    let audioEngine: AudioRecording
    let whisperService: SpeechTranscribing
    let textInjector: TextInjecting
    let hotKeyManager: HotKeyMonitoring
    let modelManager: ModelManaging
    let soundManager: SoundPlaying
    let cursorOverlay: CursorOverlayManaging
    let updateChecker = UpdateChecker()
    let permissionManager: any PermissionManaging

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    /// Whether to skip system integration calls (SMAppService, etc.) during init.
    /// Set to `true` in tests to avoid side effects.
    let skipSystemIntegration: Bool

    // MARK: - Initialization

    init(
        audioEngine: AudioRecording = AudioEngine(),
        whisperService: SpeechTranscribing = WhisperService(),
        textInjector: TextInjecting = TextInjector(),
        hotKeyManager: HotKeyMonitoring = HotKeyManager(),
        modelManager: ModelManaging = ModelManager(),
        soundManager: SoundPlaying = SoundManager(),
        cursorOverlay: CursorOverlayManaging,
        permissionManager: (any PermissionManaging)? = nil,
        skipSystemIntegration: Bool = false
    ) {
        self.audioEngine = audioEngine
        self.whisperService = whisperService
        self.textInjector = textInjector
        self.hotKeyManager = hotKeyManager
        self.modelManager = modelManager
        self.soundManager = soundManager
        self.cursorOverlay = cursorOverlay
        self.permissionManager = permissionManager ?? PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)
        self.skipSystemIntegration = skipSystemIntegration

        VocaLogger.info(.appState, "Initializing...")
        if !skipSystemIntegration {
            syncLaunchAtLogin()
        }
        setupServices()

        // Forward updateChecker changes so SwiftUI views observing AppState
        // re-render when updateState changes (nested ObservableObject fix).
        updateChecker.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Convenience factory for creating AppState with all real services.
    /// Needed because CursorOverlayManager is @MainActor and can't be a default parameter.
    @MainActor
    static func production() -> AppState {
        AppState(cursorOverlay: CursorOverlayManager())
    }

    /// Called once from the SwiftUI lifecycle to complete initialization.
    /// Safe to call multiple times — only the first call takes effect.
    func triggerStartupIfNeeded() {
        guard !hasStarted else {
            VocaLogger.debug(.appState, "triggerStartupIfNeeded called again — skipping (already started)")
            return
        }
        hasStarted = true
        Task {
            await performStartup()
        }
    }

    // MARK: - Launch at Login

    /// Sync the persisted launchAtLogin preference with SMAppService.
    /// Called once on init to reconcile state (e.g. if the user toggled it
    /// in System Settings directly, or if the app was re-installed).
    private func syncLaunchAtLogin() {
        let currentStatus = SMAppService.mainApp.status
        let isRegistered = currentStatus == .enabled

        if launchAtLogin && !isRegistered {
            // User wants launch-at-login but it's not registered — register now
            setLaunchAtLogin(true)
        } else if !launchAtLogin && isRegistered {
            // Persisted preference says disabled but system says enabled — unregister
            setLaunchAtLogin(false)
        }
    }

    /// Register or unregister the app as a login item via SMAppService.
    /// Updates the persisted `launchAtLogin` preference to match.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                VocaLogger.info(.appState, "Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                VocaLogger.info(.appState, "Unregistered as login item")
            }
            launchAtLogin = enabled
        } catch {
            VocaLogger.error(.appState, "Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
            // Revert the preference to match the actual system state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Setup

    private func setupServices() {
        // Detect system capabilities
        systemCapabilities = SystemInfo.detect()

        // Get WhisperKit's device recommendation.
        // WhisperKit's `.default` may not be in the supported list for some
        // devices. If so, fall back to the best supported model instead.
        let recommendation = modelManager.deviceRecommendation()
        let defaultIsSupported = recommendation.supported.contains(recommendation.defaultModel)
        if !defaultIsSupported, let bestSupported = recommendation.supported.last {
            deviceRecommendedModel = bestSupported
        } else {
            deviceRecommendedModel = recommendation.defaultModel
        }

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

        // Enforce monotonic support ordering: if a smaller model is unsupported,
        // all larger models must also be unsupported. This prevents contradictory
        // UI states like Medium="Too Large" but Large v3="Recommended".
        var foundUnsupported = false
        for i in availableModels.indices {
            if !availableModels[i].isSupported {
                foundUnsupported = true
            }
            if foundUnsupported {
                availableModels[i].isSupported = false
            }
        }

        // Validate that the recommended model maps to a supported ModelSize.
        // If the recommendation points to an unsupported model, fall back to
        // the largest supported model instead.
        if let recommended = deviceRecommendedModel {
            let recommendedSize = modelManager.modelSize(from: recommended)
            let isRecommendedSupported = recommendedSize.map { size in
                availableModels.first(where: { $0.size == size })?.isSupported == true
            } ?? false

            if !isRecommendedSupported {
                // Fall back to the largest supported model
                if let bestSupported = availableModels.last(where: { $0.isSupported }) {
                    deviceRecommendedModel = modelManager.whisperKitModelName(for: bestSupported.size)
                } else {
                    // No models are supported — clear the recommendation
                    deviceRecommendedModel = nil
                }
            }
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
                    VocaLogger.info(.appState, "Silence detected — auto-stopping recording (double-tap mode)")
                    await self.stopRecordingAndTranscribe()
                }
            }
        }

        // Setup max recording duration callback.
        // AudioEngine fires this when the recording reaches maxRecordingDuration.
        // This is the primary duration limit — the HotKeyManager safety timer
        // (maxRecordingDuration + 5s) acts as a backstop in case this callback
        // fails or the key-up event is lost entirely.
        audioEngine.onMaxDurationReached = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                VocaLogger.info(.appState, "Max recording duration (\(self.maxRecordingDuration)s) reached — auto-stopping")
                await self.stopRecordingAndTranscribe()
            }
        }

        // Setup audio device change callback.
        // Fires when the microphone is unplugged/replugged, Bluetooth disconnects,
        // or the default audio device changes (e.g., after sleep). AudioEngine has
        // already stopped and reset itself — we just need to recover the app state.
        audioEngine.onAudioDeviceChanged = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                VocaLogger.warning(.appState, "Audio device changed — recovering from interrupted recording")
                self.isRecording = false
                self.audioLevel = 0.0
                self.cursorOverlay.hide()
                self.hotKeyManager.resetKeyState()
                self.appStatus = .idle
                self.errorMessage = nil
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

        // Wire permission manager: start hotkey listener when permissions granted
        permissionManager.onAllPermissionsGranted = { [weak self] in
            guard let self = self else { return }
            self.hotKeyManager.startListening(
                keyCode: self.hotKeyCode,
                mode: self.activationMode,
                doubleTapThreshold: self.doubleTapThreshold,
                safetyTimeout: Double(self.maxRecordingDuration) + 5.0
            )
            VocaLogger.info(.appState, "Hotkey listener started after permission grant")
        }

        // Forward PermissionManager state changes to trigger SwiftUI updates
        permissionManager.objectWillChangePublisher
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Check permissions
        checkPermissions()
    }

    // MARK: - Permission Handling (delegated to PermissionManager)

    func checkPermissions() { permissionManager.checkPermissions() }
    func startPermissionPolling() { permissionManager.startPermissionPolling() }
    func stopPermissionPolling() { permissionManager.stopPermissionPolling() }
    var allPermissionsGranted: Bool { permissionManager.allPermissionsGranted }
    func requestMicrophonePermission() { permissionManager.requestMicrophonePermission() }
    func openMicrophoneSettings() { permissionManager.openMicrophoneSettings() }
    func requestAccessibilityPermission() { permissionManager.requestAccessibilityPermission() }
    func requestInputMonitoringPermission() { permissionManager.requestInputMonitoringPermission() }

    // MARK: - Force Recovery

    /// Forcibly reset the entire recording pipeline to idle state.
    /// This is a last-resort recovery mechanism callable from the menu bar UI.
    /// It unconditionally resets the audio engine, hotkey state, cursor overlay,
    /// and all published state back to idle.
    func forceRecovery() {
        VocaLogger.warning(.appState, "Force recovery: resetting all state to idle (was appStatus=\(appStatus.rawValue), isRecording=\(isRecording))")

        // Reset audio engine unconditionally
        audioEngine.forceReset()

        // Reset hotkey tracking state
        hotKeyManager.resetKeyState()

        // Reset UI state
        isRecording = false
        audioLevel = 0.0
        cursorOverlay.hide()
        appStatus = .idle
        errorMessage = nil
    }

    // MARK: - Recording Flow

    func startRecording() async {
        // If we're already recording, this is a recovery attempt — the user
        // pressed the hotkey again because a previous key-up was missed.
        // Stop the current recording and transcribe what we have.
        if appStatus == .recording || isRecording {
            VocaLogger.warning(.appState, "startRecording called while already recording — treating as stop (recovery)")
            await stopRecordingAndTranscribe()
            return
        }

        guard appStatus == .idle else {
            // If stuck in .processing or .error for too long, force recovery
            // so the user can start a fresh recording.
            if appStatus == .error || appStatus == .processing {
                VocaLogger.warning(.appState, "startRecording called in \(appStatus.rawValue) state — force recovering to allow new recording")
                forceRecovery()
                // Don't start recording in the same call — let the user press again
                return
            }
            VocaLogger.warning(.appState, "startRecording called in non-idle state: \(appStatus.rawValue) — ignoring")
            return
        }
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

        // Start recording immediately for instant responsiveness.
        // The start sound is played concurrently — any brief bleed into the
        // mic buffer is negligible and handled well by WhisperKit's noise model.
        audioEngine.startRecording(
            silenceThreshold: Float(silenceThreshold),
            silenceDuration: silenceDuration,
            maxDuration: TimeInterval(maxRecordingDuration)
        )

        // Play start sound after mic is active (fire-and-forget)
        if soundEffectsEnabled {
            soundManager.playStartSound()
        }
    }

    func stopRecordingAndTranscribe() async {
        // Accept stop if we're recording OR if the audio engine thinks
        // it's recording (covers stuck-state recovery scenarios where
        // isRecording and appStatus may be out of sync).
        guard isRecording || appStatus == .recording else { return }

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

            // Inject text at cursor position (text is already filtered
            // by WhisperService to remove hallucination tokens like [BLANK_AUDIO])
            let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                textInjector.inject(
                    text: trimmedText,
                    preserveClipboard: preserveClipboard
                )
            } else {
                VocaLogger.info(.appState, "Transcription produced no usable text (silence or blank audio)")
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

        // Resolve which ModelSize we're loading. When size is nil (auto-select),
        // we don't know yet — we'll detect it after loading completes.
        let targetSize = size

        // Mark the model as loading in the UI
        if let targetSize = targetSize, let idx = availableModels.firstIndex(where: { $0.size == targetSize }) {
            availableModels[idx].isLoading = true
            availableModels[idx].loadingStatus = "Preparing…"
        }

        do {
            // If model is downloaded locally, validate/repair tokenizer assets
            // before WhisperKit initializes. This avoids first-run crashes in
            // swift-transformers when it falls back to a missing bundled tokenizer.
            let folderURL = try targetSize.map { try modelManager.ensureTokenizerAssets(for: $0) }

            // Update status: unpacking
            if let targetSize = targetSize, let idx = availableModels.firstIndex(where: { $0.size == targetSize }) {
                availableModels[idx].loadingStatus = "Unpacking model…"
            }

            // Load model with status callback
            try await whisperService.loadModel(name: modelName, folder: folderURL) { [weak self] phase in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let targetSize = targetSize,
                       let idx = self.availableModels.firstIndex(where: { $0.size == targetSize }) {
                        self.availableModels[idx].loadingStatus = phase
                    }
                }
            }

            // Determine which ModelSize was actually loaded.
            // When auto-selecting, WhisperKit chooses the model and we need
            // to detect which one it picked by inspecting the loaded model name.
            let resolvedSize: ModelSize
            if let targetSize = targetSize {
                resolvedSize = targetSize
            } else {
                let loadedName = (whisperService.loadedModelName ?? "").lowercased()
                // Check from largest to smallest to avoid "base" matching inside "large-v3"
                if loadedName.contains("large") {
                    resolvedSize = .largeV3
                } else if loadedName.contains("medium") {
                    resolvedSize = .medium
                } else if loadedName.contains("small") {
                    resolvedSize = .small
                } else if loadedName.contains("base") {
                    resolvedSize = .base
                } else {
                    resolvedSize = .tiny
                }
                VocaLogger.info(.appState, "Auto-selected model resolved to: \(resolvedSize.displayName) (from '\(whisperService.loadedModelName ?? "unknown")')")
            }

            // Persist the resolved model as the user's preference
            selectedModelSize = resolvedSize.rawValue

            // Update model states — clear all, then mark the loaded one as active
            for i in availableModels.indices {
                let matches = availableModels[i].size == resolvedSize
                availableModels[i].isActive = matches
                availableModels[i].isLoading = false
                availableModels[i].loadingStatus = "Loading…"
                if matches {
                    // Refresh download status in case the auto-select downloaded it
                    availableModels[i].isDownloaded = modelManager.isModelDownloaded(resolvedSize)
                    currentModel = availableModels[i]
                }
            }

            VocaLogger.info(.appState, "Model ready: \(resolvedSize.displayName)")
        } catch {
            // Clear loading state on error for all models (covers auto-select case)
            for i in availableModels.indices {
                availableModels[i].isLoading = false
                availableModels[i].loadingStatus = "Loading…"
            }
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            VocaLogger.error(.appState, "Failed to load model: \(error.localizedDescription)")
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

        // Start polling if any permission is still missing
        startPermissionPolling()

        // 3. Load the user's preferred model.
        // On first launch the preferred model (tiny by default) won't be
        // downloaded yet. We download it explicitly so the UI can show real
        // progress, rather than delegating to WhisperKit's opaque auto-select
        // which provides no progress callbacks and may pick a different model.
        let preferredSize = ModelSize(rawValue: selectedModelSize) ?? .tiny

        if !modelManager.isModelDownloaded(preferredSize) {
            VocaLogger.info(.appState, "Preferred model \(preferredSize.displayName) not downloaded — downloading now...")
            await downloadModel(preferredSize)
        }

        VocaLogger.info(.appState, "Loading model: \(preferredSize.displayName)...")
        await loadModel(preferredSize)
        VocaLogger.info(.appState, "Model loaded: \(whisperService.loadedModelName ?? "none")")

        // 4. Always attempt to start hotkey listener
        // The event tap creation itself will fail if permissions aren't granted,
        // and we handle that gracefully in HotKeyManager.
        VocaLogger.info(.appState, "Attempting to start hotkey listener...")
        hotKeyManager.startListening(
            keyCode: hotKeyCode,
            mode: activationMode,
            doubleTapThreshold: doubleTapThreshold,
            safetyTimeout: Double(maxRecordingDuration) + 5.0
        )
        if hotKeyManager.isListening {
            VocaLogger.info(.appState, "Hotkey listener active (keyCode=\(hotKeyCode), mode=\(activationMode.rawValue))")
        } else {
            VocaLogger.warning(.appState, "Hotkey listener failed to start. Check Accessibility & Input Monitoring permissions.")
        }

        await updateChecker.checkOnLaunchIfNeeded()

        VocaLogger.info(.appState, "Startup complete!")
    }
    func completeOnboarding() {
        hasCompletedOnboarding = true
        VocaLogger.info(.appState, "Onboarding completed")
    }
}
