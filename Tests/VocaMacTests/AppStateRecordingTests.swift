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

    func testStartRecordingIgnoredInProcessingState() async {
        let appState = AppState()
        appState.appStatus = .processing

        await appState.startRecording()

        // Should remain in processing — startRecording is ignored in non-idle state
        XCTAssertEqual(appState.appStatus, .processing,
                      "startRecording should be ignored when in processing state")
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
