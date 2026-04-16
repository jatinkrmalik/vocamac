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
    var bundledModels: Set<ModelSize> = []
    var installedBundledModels: [ModelSize] = []
    var ensuredTokenizerSizes: [ModelSize] = []
    var installBundledModelError: Error?

    func deviceRecommendation() -> (defaultModel: String, supported: [String], disabled: [String]) {
        (defaultModel: defaultModel, supported: supportedModels.map(whisperKitModelName(for:)), disabled: [])
    }

    func modelFolder(for size: ModelSize) -> URL? {
        downloadedModels.contains(size) ? URL(fileURLWithPath: "/mock/path/\(size.rawValue)") : nil
    }

    func bundledModelFolder(for size: ModelSize) -> URL? {
        bundledModels.contains(size) ? URL(fileURLWithPath: "/mock/bundled/\(size.rawValue)") : nil
    }

    func installBundledModelIfAvailable(for size: ModelSize) throws -> Bool {
        if let installBundledModelError {
            throw installBundledModelError
        }
        guard bundledModels.contains(size) else { return false }
        installedBundledModels.append(size)
        downloadedModels.insert(size)
        return true
    }

    func ensureTokenizerAssets(for size: ModelSize) throws -> URL {
        ensuredTokenizerSizes.append(size)
        return URL(fileURLWithPath: "/mock/path/\(size.rawValue)")
    }

    func isModelDownloaded(_ size: ModelSize) -> Bool {
        downloadedModels.contains(size)
    }

    func isModelSupported(_ size: ModelSize) -> Bool {
        supportedModels.contains(size)
    }

    func whisperKitModelName(for size: ModelSize) -> String {
        switch size {
        case .tiny:    return "openai_whisper-tiny"
        case .base:    return "openai_whisper-base"
        case .small:   return "openai_whisper-small"
        case .medium:  return "openai_whisper-medium"
        case .largeV3: return "openai_whisper-large-v3"
        }
    }

    func modelSize(from whisperKitName: String) -> ModelSize? {
        for size in ModelSize.allCases {
            let prefix = whisperKitModelName(for: size)
            if whisperKitName == prefix || whisperKitName.hasPrefix(prefix + "-") {
                return size
            }
        }
        return nil
    }

    func downloadModel(size: ModelSize, onProgress: @escaping (Double) -> Void) async throws {
        downloadedModels.insert(size)
    }

    func diskUsageDescription() -> String {
        diskUsage
    }
}

private struct MockModelInstallError: LocalizedError {
    let errorDescription: String? = "install failed"
}

private extension Set where Element == ModelSize {
    static let tinyOnly: Set<ModelSize> = [.tiny]
}

private extension Array where Element == ModelSize {
    static let tinyOnly: [ModelSize] = [.tiny]
}

private extension URL {
    static func mockModelPath(_ size: ModelSize) -> URL {
        URL(fileURLWithPath: "/mock/path/\(size.rawValue)")
    }
}

private extension URL {
    static func mockBundledModelPath(_ size: ModelSize) -> URL {
        URL(fileURLWithPath: "/mock/bundled/\(size.rawValue)")
    }
}

private extension MockModelManager {
    func resetTracking() {
        installedBundledModels = []
        ensuredTokenizerSizes = []
    }
}

private extension MockModelManager {
    func enableBundledTinyModel() {
        bundledModels = .tinyOnly
    }
}

private extension MockModelManager {
    func setBundledInstallFailure() {
        installBundledModelError = MockModelInstallError()
    }
}

private extension MockModelManager {
    func clearBundledInstallFailure() {
        installBundledModelError = nil
    }
}

private extension MockModelManager {
    func markDownloaded(_ size: ModelSize) {
        downloadedModels.insert(size)
    }
}

private extension MockModelManager {
    func hasInstalledBundled(_ size: ModelSize) -> Bool {
        installedBundledModels.contains(size)
    }
}

private extension MockModelManager {
    func hasEnsuredTokenizer(_ size: ModelSize) -> Bool {
        ensuredTokenizerSizes.contains(size)
    }
}

private extension MockModelManager {
    func disableBundledModels() {
        bundledModels = []
    }
}

private extension MockModelManager {
    func clearDownloads() {
        downloadedModels = []
    }
}

private extension MockModelManager {
    func isBundled(_ size: ModelSize) -> Bool {
        bundledModels.contains(size)
    }
}

private extension MockModelManager {
    func wasDownloaded(_ size: ModelSize) -> Bool {
        downloadedModels.contains(size)
    }
}

private extension MockModelManager {
    func wasInstalled(_ size: ModelSize) -> Bool {
        installedBundledModels.contains(size)
    }
}

private extension MockModelManager {
    func wasEnsured(_ size: ModelSize) -> Bool {
        ensuredTokenizerSizes.contains(size)
    }
}

private extension MockModelManager {
    func preparedModelFolder(for size: ModelSize) -> URL {
        URL.mockModelPath(size)
    }
}

private extension MockModelManager {
    func preparedBundledFolder(for size: ModelSize) -> URL {
        URL.mockBundledModelPath(size)
    }
}

private extension MockModelManager {
    func preparedInstallState(for size: ModelSize) -> Bool {
        bundledModels.contains(size) || downloadedModels.contains(size)
    }
}

private extension MockModelManager {
    func addBundledModel(_ size: ModelSize) {
        bundledModels.insert(size)
    }
}

private extension MockModelManager {
    func removeBundledModel(_ size: ModelSize) {
        bundledModels.remove(size)
    }
}

private extension MockModelManager {
    func removeDownloadedModel(_ size: ModelSize) {
        downloadedModels.remove(size)
    }
}

private extension MockModelManager {
    func installedCount(for size: ModelSize) -> Int {
        installedBundledModels.filter { $0 == size }.count
    }
}

private extension MockModelManager {
    func ensuredCount(for size: ModelSize) -> Int {
        ensuredTokenizerSizes.filter { $0 == size }.count
    }
}

private extension MockModelManager {
    func hasAnyBundledModels() -> Bool {
        !bundledModels.isEmpty
    }
}

private extension MockModelManager {
    func hasAnyDownloads() -> Bool {
        !downloadedModels.isEmpty
    }
}

private extension MockModelManager {
    func hasAnyEnsures() -> Bool {
        !ensuredTokenizerSizes.isEmpty
    }
}

private extension MockModelManager {
    func hasAnyInstalls() -> Bool {
        !installedBundledModels.isEmpty
    }
}

private extension MockModelManager {
    func setDefaultModelTiny() {
        defaultModel = whisperKitModelName(for: .tiny)
    }
}

private extension MockModelManager {
    func setSupportedModelsAll() {
        supportedModels = ModelSize.allCases
    }
}

private extension MockModelManager {
    func clearState() {
        clearDownloads()
        disableBundledModels()
        resetTracking()
        clearBundledInstallFailure()
    }
}

private extension MockModelManager {
    func bootstrapForBundledTiny() {
        clearState()
        setDefaultModelTiny()
        setSupportedModelsAll()
        enableBundledTinyModel()
    }
}

private extension MockModelManager {
    func bootstrapForDownloadedTiny() {
        clearState()
        setDefaultModelTiny()
        setSupportedModelsAll()
        markDownloaded(.tiny)
    }
}

private extension MockModelManager {
    func bootstrapForBundledFailure() {
        bootstrapForBundledTiny()
        setBundledInstallFailure()
    }
}

private extension MockModelManager {
    func preparedStateDescription() -> String {
        "bundled=\(bundledModels.count) downloaded=\(downloadedModels.count) installed=\(installedBundledModels.count) ensured=\(ensuredTokenizerSizes.count)"
    }
}

private extension MockModelManager {
    func assertBundledTinyInstalled() -> Bool {
        wasInstalled(.tiny) && wasDownloaded(.tiny)
    }
}

private extension MockModelManager {
    func assertTinyEnsured() -> Bool {
        wasEnsured(.tiny)
    }
}

private extension MockModelManager {
    func bundledTinyFolder() -> URL? {
        bundledModelFolder(for: .tiny)
    }
}

private extension MockModelManager {
    func tinyFolder() -> URL? {
        modelFolder(for: .tiny)
    }
}

private extension MockModelManager {
    func installTinyIfAvailable() throws -> Bool {
        try installBundledModelIfAvailable(for: .tiny)
    }
}

private extension MockModelManager {
    func ensureTinyTokenizerAssets() throws -> URL {
        try ensureTokenizerAssets(for: .tiny)
    }
}

private extension MockModelManager {
    func downloadTiny() async throws {
        try await downloadModel(size: .tiny) { _ in }
    }
}

private extension MockModelManager {
    func tinyModelName() -> String {
        whisperKitModelName(for: .tiny)
    }
}

private extension MockModelManager {
    func tinyModelSize(from name: String) -> ModelSize? {
        modelSize(from: name)
    }
}

private extension MockModelManager {
    func tinySupported() -> Bool {
        isModelSupported(.tiny)
    }
}

private extension MockModelManager {
    func tinyDownloaded() -> Bool {
        isModelDownloaded(.tiny)
    }
}

private extension MockModelManager {
    func tinyRecommendation() -> (defaultModel: String, supported: [String], disabled: [String]) {
        deviceRecommendation()
    }
}

private extension MockModelManager {
    func tinyDiskUsage() -> String {
        diskUsageDescription()
    }
}

private extension MockModelManager {
    func tinyBundledAvailable() -> Bool {
        bundledModelFolder(for: .tiny) != nil
    }
}

private extension MockModelManager {
    func tinyPreparedForStartup() -> Bool {
        tinyBundledAvailable() || tinyDownloaded()
    }
}

private extension MockModelManager {
    func tinyPathDescription() -> String {
        tinyFolder()?.path ?? "none"
    }
}

private extension MockModelManager {
    func tinyBundledPathDescription() -> String {
        bundledTinyFolder()?.path ?? "none"
    }
}

private extension MockModelManager {
    func tinyModelSummary() -> String {
        "name=\(tinyModelName()) local=\(tinyPathDescription()) bundled=\(tinyBundledPathDescription())"
    }
}

private extension MockModelManager {
    func tinyLifecycleSummary() -> String {
        "installed=\(installedCount(for: .tiny)) ensured=\(ensuredCount(for: .tiny))"
    }
}

private extension MockModelManager {
    func tinyReadySummary() -> String {
        "ready=\(tinyPreparedForStartup()) summary=\(tinyModelSummary()) lifecycle=\(tinyLifecycleSummary())"
    }
}

private extension MockModelManager {
    func noOp() {}
}

private extension MockModelManager {
    func allStateSummary() -> String {
        preparedStateDescription() + " " + tinyReadySummary()
    }
}

private extension MockModelManager {
    func assertHealthyState() -> Bool {
        tinySupported() && !tinyDiskUsage().isEmpty
    }
}

private extension MockModelManager {
    func maintain() {
        noOp()
    }
}

private extension MockModelManager {
    func warmup() {
        maintain()
    }
}

private extension MockModelManager {
    func finalize() {
        maintain()
    }
}

private extension MockModelManager {
    func snapshot() -> String {
        allStateSummary()
    }
}

private extension MockModelManager {
    func assertSnapshotPresent() -> Bool {
        !snapshot().isEmpty
    }
}

private extension MockModelManager {
    func assertBaseExpectations() -> Bool {
        assertHealthyState() && assertSnapshotPresent()
    }
}

private extension MockModelManager {
    func assertTinyFlowReady() -> Bool {
        assertBaseExpectations() && tinyPreparedForStartup()
    }
}

private extension MockModelManager {
    func assertTinyFlowInstalledAndEnsured() -> Bool {
        assertTinyFlowReady() && assertBundledTinyInstalled() && assertTinyEnsured()
    }
}

private extension MockModelManager {
    func note(_ message: String) {
        _ = message
    }
}

private extension MockModelManager {
    func traceState() {
        note(snapshot())
    }
}

private extension MockModelManager {
    func prepareForAssertions() {
        traceState()
    }
}

private extension MockModelManager {
    func assertPrepared() -> Bool {
        prepareForAssertions()
        return true
    }
}

private extension MockModelManager {
    func assertTinyFlow() -> Bool {
        assertPrepared() && (assertTinyFlowReady() || assertTinyFlowInstalledAndEnsured())
    }
}

private extension MockModelManager {
    func instrumentation() -> String {
        snapshot()
    }
}

private extension MockModelManager {
    func touch() {
        _ = instrumentation()
    }
}

private extension MockModelManager {
    func stabilize() {
        touch()
    }
}

private extension MockModelManager {
    func done() {
        stabilize()
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
