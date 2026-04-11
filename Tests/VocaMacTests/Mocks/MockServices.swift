// MockServices.swift
// VocaMac Tests
//
// Mock implementations of service protocols for unit testing.
// These avoid triggering real system side effects (sounds, permissions, mic, etc.).

import Foundation
import Combine
@testable import VocaMac

// MARK: - MockAudioEngine

final class MockAudioEngine: AudioRecording {
    var isCurrentlyRecording = false
    var onAudioLevel: ((Float) -> Void)?
    var onSilenceDetected: (() -> Void)?
    var onMaxDurationReached: (() -> Void)?
    var onAudioDeviceChanged: (() -> Void)?

    var lastSilenceThreshold: Float?
    var lastSilenceDuration: Double?
    var lastMaxDuration: TimeInterval?
    var stopRecordingResult: [Float] = []
    var forceResetCallCount = 0

    private var permissionStatus: PermissionStatus = .granted

    func startRecording(silenceThreshold: Float, silenceDuration: Double, maxDuration: TimeInterval) {
        isCurrentlyRecording = true
        lastSilenceThreshold = silenceThreshold
        lastSilenceDuration = silenceDuration
        lastMaxDuration = maxDuration
    }

    @discardableResult
    func stopRecording() -> [Float] {
        isCurrentlyRecording = false
        return stopRecordingResult
    }

    func forceReset() {
        forceResetCallCount += 1
        isCurrentlyRecording = false
    }

    func checkPermissionStatus() -> PermissionStatus {
        permissionStatus
    }

    func setPermissionStatus(_ status: PermissionStatus) {
        permissionStatus = status
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        completion(permissionStatus == .granted)
    }
}

// MARK: - MockSoundManager

final class MockSoundManager: SoundPlaying {
    var volume: Float = 0.5
    var startSoundCallCount = 0
    var stopSoundCallCount = 0
    var startSoundAsyncCallCount = 0
    var stopSoundAsyncCallCount = 0

    func playStartSound() {
        startSoundCallCount += 1
    }

    func playStartSoundAsync() async {
        startSoundAsyncCallCount += 1
    }

    func playStopSound() {
        stopSoundCallCount += 1
    }

    func playStopSoundAsync() async {
        stopSoundAsyncCallCount += 1
    }
}

// MARK: - MockHotKeyManager

final class MockHotKeyManager: HotKeyMonitoring {
    var isListening = false
    var eventTap: CFMachPort? = nil
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    var startListeningCallCount = 0
    var lastKeyCode: Int?
    var lastMode: ActivationMode?
    var lastDoubleTapThreshold: Double?
    var lastSafetyTimeout: Double?
    var resetKeyStateCallCount = 0

    private var accessibilityPermission = false

    func checkAccessibilityPermission(prompt: Bool) -> Bool {
        accessibilityPermission
    }

    func setAccessibilityPermission(_ granted: Bool) {
        accessibilityPermission = granted
    }

    func startListening(keyCode: Int, mode: ActivationMode, doubleTapThreshold: Double, safetyTimeout: Double) {
        startListeningCallCount += 1
        lastKeyCode = keyCode
        lastMode = mode
        lastDoubleTapThreshold = doubleTapThreshold
        lastSafetyTimeout = safetyTimeout
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    func resetKeyState() {
        resetKeyStateCallCount += 1
    }

    func _updateConfiguration(keyCode: Int?, mode: ActivationMode?, doubleTapThreshold: Double?, safetyTimeout: Double?) {
    }
}

// MARK: - MockPermissionManager

@MainActor
final class MockPermissionManager: ObservableObject, PermissionManaging {
    @Published var micPermission: PermissionStatus = .granted
    @Published var accessibilityPermission: PermissionStatus = .granted
    @Published var inputMonitoringPermission: PermissionStatus = .granted
    var onAllPermissionsGranted: (() -> Void)?

    var checkPermissionsCallCount = 0
    var startPollingCallCount = 0
    var stopPollingCallCount = 0
    var requestMicPermissionCallCount = 0
    var openMicSettingsCallCount = 0
    var requestAccessibilityCallCount = 0
    var requestInputMonitoringCallCount = 0

    var objectWillChangePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    var allPermissionsGranted: Bool {
        micPermission == .granted &&
        accessibilityPermission == .granted &&
        inputMonitoringPermission == .granted
    }

    func checkPermissions() {
        checkPermissionsCallCount += 1
    }

    func startPermissionPolling() {
        startPollingCallCount += 1
    }

    func stopPermissionPolling() {
        stopPollingCallCount += 1
    }

    func requestMicrophonePermission() {
        requestMicPermissionCallCount += 1
    }

    func openMicrophoneSettings() {
        openMicSettingsCallCount += 1
    }

    func requestAccessibilityPermission() {
        requestAccessibilityCallCount += 1
    }

    func requestInputMonitoringPermission() {
        requestInputMonitoringCallCount += 1
    }
}

// MARK: - MockCursorOverlay

@MainActor
final class MockCursorOverlay: CursorOverlayManaging {
    var showCallCount = 0
    var hideCallCount = 0
    var transitionCallCount = 0
    var lastAudioLevel: Float?

    func show() {
        showCallCount += 1
    }

    func hide() {
        hideCallCount += 1
    }

    func transitionToProcessing() {
        transitionCallCount += 1
    }

    func updateAudioLevel(_ level: Float) {
        lastAudioLevel = level
    }
}

// MARK: - MockModelManager

final class MockModelManager: ModelManaging {
    var supportedModels: [ModelSize] = ModelSize.allCases
    var defaultModel: String = "openai_whisper-tiny"
    var downloadedModels: Set<ModelSize> = []
    var diskUsage: String = "100 MB"

    func deviceRecommendation() -> (defaultModel: String, supported: [String], disabled: [String]) {
        (defaultModel: defaultModel, supported: supportedModels.map(\.rawValue), disabled: [])
    }

    func modelFolder(for size: ModelSize) -> URL? {
        downloadedModels.contains(size) ? URL(fileURLWithPath: "/mock/path/\(size.rawValue)") : nil
    }

    func isModelDownloaded(_ size: ModelSize) -> Bool {
        downloadedModels.contains(size)
    }

    func isModelSupported(_ size: ModelSize) -> Bool {
        supportedModels.contains(size)
    }

    func whisperKitModelName(for size: ModelSize) -> String {
        "openai_whisper-\(size.rawValue)"
    }

    func downloadModel(size: ModelSize, onProgress: @escaping (Double) -> Void) async throws {
        downloadedModels.insert(size)
    }

    func diskUsageDescription() -> String {
        diskUsage
    }
}

// MARK: - MockWhisperService

final class MockWhisperService: SpeechTranscribing {
    var loadedModelName: String? = "openai_whisper-tiny"
    var isModelLoaded: Bool = true
    var lastTranscribedAudioData: [Float]?
    var lastLanguage: String?
    var lastTranslate: Bool?
    var mockTranscriptionResult: VocaTranscription = VocaTranscription(text: "mock transcription", duration: 1.0, detectedLanguage: "en", audioLengthSeconds: 1.0, modelUsed: .tiny)
    var shouldThrow = false

    func transcribe(audioData: [Float], language: String?, translate: Bool) async throws -> VocaTranscription {
        lastTranscribedAudioData = audioData
        lastLanguage = language
        lastTranslate = translate
        if shouldThrow {
            throw WhisperError.transcriptionFailed(reason: "mock error")
        }
        return mockTranscriptionResult
    }

    func _loadModel(name: String?, folder: URL?, onPhaseChange: ((String) -> Void)?) async throws {
        loadedModelName = name ?? "mock-model"
        isModelLoaded = true
    }
}

// MARK: - MockTextInjector

final class MockTextInjector: TextInjecting {
    var injectCallCount = 0
    var lastInjectedText: String?
    var lastPreserveClipboard: Bool?

    func inject(text: String, preserveClipboard: Bool) {
        injectCallCount += 1
        lastInjectedText = text
        lastPreserveClipboard = preserveClipboard
    }
}

// MARK: - Test Helper

extension AppState {
    @MainActor
    static func makeTestState() -> (appState: AppState, mocks: TestMocks) {
        let audioEngine = MockAudioEngine()
        let soundManager = MockSoundManager()
        let hotKeyManager = MockHotKeyManager()
        let permissionManager = MockPermissionManager()
        let cursorOverlay = MockCursorOverlay()
        let modelManager = MockModelManager()
        let whisperService = MockWhisperService()
        let textInjector = MockTextInjector()

        let mocks = TestMocks(
            audioEngine: audioEngine,
            soundManager: soundManager,
            hotKeyManager: hotKeyManager,
            permissionManager: permissionManager,
            cursorOverlay: cursorOverlay,
            modelManager: modelManager,
            whisperService: whisperService,
            textInjector: textInjector
        )
        let appState = AppState(
            audioEngine: audioEngine,
            whisperService: whisperService,
            textInjector: textInjector,
            hotKeyManager: hotKeyManager,
            modelManager: modelManager,
            soundManager: soundManager,
            cursorOverlay: cursorOverlay,
            permissionManager: permissionManager,
            skipSystemIntegration: true
        )
        return (appState, mocks)
    }
}

struct TestMocks {
    let audioEngine: MockAudioEngine
    let soundManager: MockSoundManager
    let hotKeyManager: MockHotKeyManager
    let permissionManager: MockPermissionManager
    let cursorOverlay: MockCursorOverlay
    let modelManager: MockModelManager
    let whisperService: MockWhisperService
    let textInjector: MockTextInjector
}
