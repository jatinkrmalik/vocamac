// AppStateRecordingTests.swift
// VocaMac
//
// Tests for AppState recording flow and state transitions.

import XCTest
@testable import VocaMac

// MARK: - AppState Recording State Transition Tests

@MainActor
final class AppStateRecordingTests: XCTestCase {

    func testInitialState() {
        let appState = AppState()

        XCTAssertEqual(appState.appStatus, .idle, "App should start in idle state")
        XCTAssertFalse(appState.isRecording, "Should not be recording initially")
        XCTAssertNil(appState.errorMessage, "No error message initially")
        XCTAssertEqual(appState.audioLevel, 0.0, "Audio level should be zero")
    }

    func testStartRecordingWithDeniedMicPermission() async {
        let appState = AppState()

        // Force mic permission to denied state to test the guard
        appState.permissionManager.micPermission = .denied

        await appState.startRecording()

        XCTAssertEqual(appState.appStatus, .error,
                      "Should transition to error when mic permission is denied")
        XCTAssertNotNil(appState.errorMessage,
                       "Should set an error message about microphone permission")
        XCTAssertTrue(appState.errorMessage?.contains("Microphone") == true,
                     "Error message should mention microphone")
    }

    func testStartRecordingInProcessingStateForceRecovers() async {
        let appState = AppState()
        appState.appStatus = .processing

        await appState.startRecording()

        // PR #84 changed behavior: startRecording in processing/error state now
        // force-recovers to idle so the user can unstick the app by pressing
        // the hotkey again (instead of silently ignoring the press).
        XCTAssertEqual(appState.appStatus, .idle,
                      "startRecording in processing state should force recover to idle")
    }

    func testStopRecordingWhenNotRecording() async {
        let appState = AppState()

        // Stopping when not recording should be a no-op
        await appState.stopRecordingAndTranscribe()

        XCTAssertEqual(appState.appStatus, .idle,
                      "Should remain idle when stopping without recording")
        XCTAssertFalse(appState.isRecording)
    }

    func testStopRecordingResetsAudioLevel() async {
        let appState = AppState()
        appState.isRecording = true
        appState.appStatus = .recording
        appState.audioLevel = 0.75

        await appState.stopRecordingAndTranscribe()

        XCTAssertEqual(appState.audioLevel, 0.0,
                      "Audio level should be reset to 0 after stopping")
        XCTAssertFalse(appState.isRecording,
                      "isRecording should be false after stopping")
    }

    func testStopRecordingWithEmptyAudioReturnsToIdle() async {
        let appState = AppState()
        appState.isRecording = true
        appState.appStatus = .recording

        // stopRecording will call audioEngine.stopRecording() which returns
        // empty data (no actual recording happened)
        await appState.stopRecordingAndTranscribe()

        XCTAssertEqual(appState.appStatus, .idle,
                      "Should return to idle when audio data is empty")
    }

    func testSelectedModelSizeDefault() {
        let appState = AppState()

        XCTAssertEqual(appState.selectedModelSize, ModelSize.tiny.rawValue,
                      "Default model size should be tiny")
    }

    func testPreserveClipboardDefault() {
        let appState = AppState()

        XCTAssertTrue(appState.preserveClipboard,
                     "preserveClipboard should default to true")
    }

    func testSoundEffectsEnabledDefault() {
        let appState = AppState()

        XCTAssertTrue(appState.soundEffectsEnabled,
                     "Sound effects should be enabled by default")
    }

    func testShowCursorIndicatorDefault() {
        let appState = AppState()

        XCTAssertTrue(appState.showCursorIndicator,
                     "Cursor indicator should be shown by default")
    }

    func testTranslationDisabledByDefault() {
        let appState = AppState()

        XCTAssertFalse(appState.translationEnabled,
                      "Translation should be disabled by default")
    }

    func testSelectedLanguageDefault() {
        let appState = AppState()

        XCTAssertEqual(appState.selectedLanguage, "auto",
                      "Default language should be 'auto'")
    }

    func testActivationModeDefault() {
        let appState = AppState()

        XCTAssertEqual(appState.activationMode, .pushToTalk,
                      "Default activation mode should be push-to-talk")
    }

    func testDoubleTapThresholdDefault() {
        let appState = AppState()

        XCTAssertEqual(appState.doubleTapThreshold, 0.4,
                      "Default double-tap threshold should be 0.4 seconds")
    }

    func testMaxRecordingDurationDefault() {
        let appState = AppState()

        XCTAssertEqual(appState.maxRecordingDuration, 60,
                      "Default max recording duration should be 60 seconds")
    }

    func testAvailableModelsPopulated() {
        let appState = AppState()

        XCTAssertFalse(appState.availableModels.isEmpty,
                      "Available models should be populated on init")
        XCTAssertEqual(appState.availableModels.count, ModelSize.allCases.count,
                      "Should have one entry per ModelSize")
    }

    func testSystemCapabilitiesDetected() {
        let appState = AppState()

        XCTAssertNotNil(appState.systemCapabilities,
                       "System capabilities should be detected on init")
    }

    func testDeviceRecommendedModelSet() {
        let appState = AppState()

        XCTAssertNotNil(appState.deviceRecommendedModel,
                       "Device recommended model should be set on init")
    }

    func testPermissionManagerIntegration() {
        let appState = AppState()

        // PermissionManager should be accessible
        XCTAssertNotNil(appState.permissionManager,
                       "PermissionManager should be initialized")

        // Permission state should flow through
        let mic = appState.micPermission
        XCTAssertEqual(mic, appState.permissionManager.micPermission,
                      "micPermission should delegate to PermissionManager")
    }

    func testTriggerStartupIdempotent() {
        let appState = AppState()

        // Should be safe to call multiple times
        appState.triggerStartupIfNeeded()
        appState.triggerStartupIfNeeded()
        appState.triggerStartupIfNeeded()
        // No crash = pass
    }
}

// MARK: - AppState Error Recovery Tests

@MainActor
final class AppStateErrorRecoveryTests: XCTestCase {

    func testErrorStateCanBeCleared() {
        let appState = AppState()
        appState.appStatus = .error
        appState.errorMessage = "Test error"

        // Manually clear error
        appState.appStatus = .idle
        appState.errorMessage = nil

        XCTAssertEqual(appState.appStatus, .idle)
        XCTAssertNil(appState.errorMessage)
    }

    func testStartRecordingWhileRecordingTriggersRecovery() async {
        let appState = AppState()
        appState.isRecording = true
        appState.appStatus = .recording

        // Calling startRecording while already recording should trigger
        // the recovery path (stop + transcribe)
        await appState.startRecording()

        // After recovery, should not be recording
        XCTAssertFalse(appState.isRecording,
                      "Recovery path should stop recording")
    }
}

// MARK: - AppState Force Recovery Tests

final class AppStateForceRecoveryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up persisted state
        UserDefaults.standard.removeObject(forKey: "vocamac.hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
    }

    @MainActor
    func testForceRecoveryResetsToIdle() {
        let appState = AppState()

        // Simulate a stuck recording state
        appState.appStatus = .recording
        appState.isRecording = true
        appState.audioLevel = 0.5

        appState.forceRecovery()

        XCTAssertEqual(appState.appStatus, .idle,
            "appStatus should be idle after force recovery")
        XCTAssertFalse(appState.isRecording,
            "isRecording should be false after force recovery")
        XCTAssertEqual(appState.audioLevel, 0.0,
            "audioLevel should be 0 after force recovery")
        XCTAssertNil(appState.errorMessage,
            "errorMessage should be nil after force recovery")
    }

    @MainActor
    func testForceRecoveryFromErrorState() {
        let appState = AppState()

        appState.appStatus = .error
        appState.errorMessage = "Something went wrong"

        appState.forceRecovery()

        XCTAssertEqual(appState.appStatus, .idle,
            "appStatus should be idle after force recovery from error")
        XCTAssertNil(appState.errorMessage,
            "errorMessage should be cleared after force recovery")
    }

    @MainActor
    func testForceRecoveryFromProcessingState() {
        let appState = AppState()

        appState.appStatus = .processing
        appState.isRecording = false

        appState.forceRecovery()

        XCTAssertEqual(appState.appStatus, .idle,
            "appStatus should be idle after force recovery from processing")
    }

    @MainActor
    func testForceRecoveryWhenAlreadyIdle() {
        // Force recovery should be safe to call when already idle
        let appState = AppState()

        XCTAssertEqual(appState.appStatus, .idle)

        appState.forceRecovery()

        XCTAssertEqual(appState.appStatus, .idle,
            "appStatus should remain idle")
        XCTAssertFalse(appState.isRecording)
        XCTAssertNil(appState.errorMessage)
    }

    @MainActor
    func testForceRecoveryMultipleTimes() {
        // Calling forceRecovery multiple times should be safe
        let appState = AppState()
        appState.appStatus = .recording
        appState.isRecording = true

        appState.forceRecovery()
        appState.forceRecovery()
        appState.forceRecovery()

        XCTAssertEqual(appState.appStatus, .idle)
        XCTAssertFalse(appState.isRecording)
    }
}

// MARK: - AppState Recording State Guard Tests

final class AppStateRecordingGuardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "vocamac.hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
    }

    @MainActor
    func testStartRecordingInErrorStateForceRecovers() async {
        let appState = AppState()
        appState.appStatus = .error
        appState.errorMessage = "Previous error"

        await appState.startRecording()

        // Should have force-recovered to idle (not started recording in same call)
        XCTAssertEqual(appState.appStatus, .idle,
            "startRecording in error state should force recover to idle")
        XCTAssertNil(appState.errorMessage,
            "Error message should be cleared after force recovery")
    }

    @MainActor
    func testStartRecordingInProcessingStateForceRecovers() async {
        let appState = AppState()
        appState.appStatus = .processing

        await appState.startRecording()

        XCTAssertEqual(appState.appStatus, .idle,
            "startRecording in processing state should force recover to idle")
    }

    @MainActor
    func testStopRecordingWhenNotRecordingIsNoop() async {
        let appState = AppState()
        XCTAssertEqual(appState.appStatus, .idle)
        XCTAssertFalse(appState.isRecording)

        await appState.stopRecordingAndTranscribe()

        // Should still be idle — no crash, no state change
        XCTAssertEqual(appState.appStatus, .idle)
        XCTAssertFalse(appState.isRecording)
    }

    @MainActor
    func testInitialStateIsIdle() {
        let appState = AppState()
        XCTAssertEqual(appState.appStatus, .idle)
        XCTAssertFalse(appState.isRecording)
        XCTAssertEqual(appState.audioLevel, 0.0)
        XCTAssertNil(appState.errorMessage)
    }
}
