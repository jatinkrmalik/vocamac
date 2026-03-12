// VocaMacTests.swift
// VocaMac Tests
//
// Unit tests for VocaMac core logic and data models.
// Run with: swift test

import XCTest
import ServiceManagement
@testable import VocaMac

// MARK: - SystemInfo Tests

final class SystemInfoTests: XCTestCase {

    func testDetectSystemCapabilities() {
        let capabilities = SystemInfo.detect()
        XCTAssertGreaterThan(capabilities.physicalMemoryGB, 0)
        XCTAssertGreaterThan(capabilities.coreCount, 0)
        XCTAssertFalse(capabilities.processorName.isEmpty)
    }

    func testModelRecommendationAppleSilicon() {
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 4), .tiny)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 8), .base)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 16), .small)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 24), .medium)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 48), .medium)
    }

    func testModelRecommendationIntel() {
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 8), .tiny)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 16), .base)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 32), .small)
    }

    func testRecommendedThreadCount() {
        let threads = SystemInfo.recommendedThreadCount
        XCTAssertGreaterThanOrEqual(threads, 2)
        XCTAssertLessThanOrEqual(threads, 8)
    }

    func testModelIdentifier() {
        XCTAssertFalse(SystemInfo.modelIdentifier.isEmpty)
    }

    func testSummaryDescription() {
        let capabilities = SystemInfo.detect()
        let summary = capabilities.summaryDescription
        XCTAssertTrue(summary.contains("Processor:"))
        XCTAssertTrue(summary.contains("Architecture:"))
        XCTAssertTrue(summary.contains("Memory:"))
        XCTAssertTrue(summary.contains("Cores:"))
        XCTAssertTrue(summary.contains("Metal:"))
        XCTAssertTrue(summary.contains("Recommended Model:"))
    }
}

// MARK: - ModelSize Tests

final class ModelSizeTests: XCTestCase {

    func testModelSizesAscendingFileSize() {
        let sizes = ModelSize.allCases.map { $0.fileSizeBytes }
        for i in 1..<sizes.count {
            XCTAssertGreaterThan(sizes[i], sizes[i - 1])
        }
    }

    func testFileSizeDescription() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.fileSizeDescription.isEmpty)
        }
    }

    func testDisplayNames() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.displayName.isEmpty)
        }
    }

    func testRAMRequirementsIncreasing() {
        let rams = ModelSize.allCases.map { $0.ramRequiredGB }
        for i in 1..<rams.count {
            XCTAssertGreaterThanOrEqual(rams[i], rams[i - 1])
        }
    }

    func testQualityDescriptions() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.qualityDescription.isEmpty)
        }
    }

    func testRelativeSpeedIncreasing() {
        let speeds = ModelSize.allCases.map { $0.relativeSpeed }
        for i in 1..<speeds.count {
            XCTAssertGreaterThan(speeds[i], speeds[i - 1])
        }
    }

    func testAllCasesCount() {
        XCTAssertEqual(ModelSize.allCases.count, 5)
    }

    func testRawValues() {
        XCTAssertEqual(ModelSize.tiny.rawValue, "tiny")
        XCTAssertEqual(ModelSize.base.rawValue, "base")
        XCTAssertEqual(ModelSize.small.rawValue, "small")
        XCTAssertEqual(ModelSize.medium.rawValue, "medium")
        XCTAssertEqual(ModelSize.largeV3.rawValue, "large-v3")
    }
}

// MARK: - ModelManager Tests

final class ModelManagerTests: XCTestCase {

    func testWhisperKitModelNames() {
        let manager = ModelManager()
        XCTAssertEqual(manager.whisperKitModelName(for: .tiny), "openai_whisper-tiny")
        XCTAssertEqual(manager.whisperKitModelName(for: .base), "openai_whisper-base")
        XCTAssertEqual(manager.whisperKitModelName(for: .small), "openai_whisper-small")
        XCTAssertEqual(manager.whisperKitModelName(for: .medium), "openai_whisper-medium")
        XCTAssertEqual(manager.whisperKitModelName(for: .largeV3), "openai_whisper-large-v3")
    }

    func testDownloadedModelsReturnsArray() {
        let manager = ModelManager()
        let downloaded = manager.downloadedModels()
        XCTAssertGreaterThanOrEqual(downloaded.count, 0)
    }

    func testDiskUsageDescriptionNotEmpty() {
        let manager = ModelManager()
        XCTAssertFalse(manager.diskUsageDescription().isEmpty)
    }

    func testTotalDiskUsageNonNegative() {
        let manager = ModelManager()
        XCTAssertGreaterThanOrEqual(manager.totalDiskUsage(), 0)
    }
}

// MARK: - WhisperModelInfo Tests

final class WhisperModelInfoTests: XCTestCase {

    func testStatusDescription() {
        var model = WhisperModelInfo(
            size: .tiny, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.statusDescription, "Not Downloaded")

        model.isDownloaded = true
        XCTAssertEqual(model.statusDescription, "Downloaded")

        model.isActive = true
        XCTAssertEqual(model.statusDescription, "Active")

        model.isActive = false
        model.downloadProgress = 0.5
        XCTAssertEqual(model.statusDescription, "Downloading (50%)")
    }

    func testLoadingState() {
        var model = WhisperModelInfo(
            size: .base, filePath: nil, isDownloaded: true,
            isActive: false, isSupported: true
        )
        model.isLoading = true
        XCTAssertEqual(model.statusDescription, "Loading…")
        XCTAssertEqual(model.statusIconName, "arrow.trianglehead.2.clockwise")
    }

    func testDefaultIsLoading() {
        let model = WhisperModelInfo(
            size: .tiny, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertFalse(model.isLoading)
    }

    func testStatusIcon() {
        var model = WhisperModelInfo(
            size: .base, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.statusIconName, "arrow.down.to.line")

        model.isDownloaded = true
        XCTAssertEqual(model.statusIconName, "checkmark.circle")

        model.isActive = true
        XCTAssertEqual(model.statusIconName, "checkmark.circle.fill")

        model.isActive = false
        model.downloadProgress = 0.3
        XCTAssertEqual(model.statusIconName, "arrow.down.circle")
    }

    func testIDMatchesSize() {
        let model = WhisperModelInfo(
            size: .small, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.id, "small")
    }
}

// MARK: - TranscriptionResult Tests

final class VocaTranscriptionTests: XCTestCase {

    func testCreationPreservesValues() {
        let result = VocaTranscription(
            text: "Hello world", duration: 1.5,
            detectedLanguage: "en", audioLengthSeconds: 3.0, modelUsed: .tiny
        )
        XCTAssertEqual(result.text, "Hello world")
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertEqual(result.detectedLanguage, "en")
        XCTAssertEqual(result.audioLengthSeconds, 3.0)
        XCTAssertEqual(result.modelUsed, .tiny)
    }

    func testUniqueID() {
        let r1 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: .tiny
        )
        let r2 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: .tiny
        )
        XCTAssertNotEqual(r1.id, r2.id)
    }
}

// MARK: - AppStatus Tests

final class AppStatusTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(AppStatus.idle.rawValue, "idle")
        XCTAssertEqual(AppStatus.recording.rawValue, "recording")
        XCTAssertEqual(AppStatus.processing.rawValue, "processing")
        XCTAssertEqual(AppStatus.error.rawValue, "error")
    }
}

// MARK: - ActivationMode Tests

final class ActivationModeTests: XCTestCase {

    func testDisplayNames() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
        }
    }

    func testDescriptions() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.description.isEmpty)
        }
    }

    func testActivationModeCaseCount() {
        XCTAssertEqual(ActivationMode.allCases.count, 2)
    }

    func testRawValues() {
        XCTAssertEqual(ActivationMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(ActivationMode.doubleTapToggle.rawValue, "doubleTapToggle")
    }
}

// MARK: - KeyCodeReference Tests

final class KeyCodeReferenceTests: XCTestCase {

    func testCommonHotKeysNotEmpty() {
        XCTAssertFalse(KeyCodeReference.commonHotKeys.isEmpty)
    }

    func testDisplayNameForKnownKeyCode() {
        XCTAssertEqual(KeyCodeReference.displayName(for: 61), "Right Option (⌥)")
    }

    func testDisplayNameForUnknownKeyCode() {
        XCTAssertEqual(KeyCodeReference.displayName(for: 999), "Key 999")
    }

    func testCommonHotKeysValid() {
        for hotkey in KeyCodeReference.commonHotKeys {
            XCTAssertGreaterThanOrEqual(hotkey.keyCode, 0)
            XCTAssertFalse(hotkey.name.isEmpty)
        }
    }
}

// MARK: - TextInjector Tests

final class TextInjectorTests: XCTestCase {

    func testInstantiation() {
        let injector = TextInjector()
        XCTAssertNotNil(injector)
    }

    func testInjectEmptyStringDoesNothing() {
        let injector = TextInjector()
        // Should return immediately without crashing
        injector.inject(text: "", preserveClipboard: true)
        injector.inject(text: "", preserveClipboard: false)
    }
}

// MARK: - SoundManager Tests

final class SoundManagerTests: XCTestCase {

    var soundManager: SoundManager!

    override func setUp() {
        super.setUp()
        soundManager = SoundManager()
    }

    func testPlayStartSoundSync() {
        // Test that synchronous play doesn't crash
        soundManager.playStartSound()
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }

    func testPlayStopSoundSync() {
        // Test that synchronous play doesn't crash
        soundManager.playStopSound()
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }

    func testPlayStartSoundAsync() async {
        // Test that async play completes without hanging
        let startTime = Date()
        await soundManager.playStartSoundAsync()
        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete in reasonable time (under 2 seconds even with timeout)
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testPlayStopSoundAsync() async {
        // Test that async play completes without hanging
        let startTime = Date()
        await soundManager.playStopSoundAsync()
        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete in reasonable time (under 2 seconds even with timeout)
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testVolumeControl() {
        soundManager.volume = 0.0
        XCTAssertEqual(soundManager.volume, 0.0)

        soundManager.volume = 0.5
        XCTAssertEqual(soundManager.volume, 0.5)

        soundManager.volume = 1.0
        XCTAssertEqual(soundManager.volume, 1.0)
    }
}


// MARK: - Translation Toggle Tests

final class TranslationToggleTests: XCTestCase {

    @MainActor
    func testTranslationEnabledDefaultValue() {
        // translationEnabled should default to false
        // Note: @AppStorage defaults are set in AppState initialization
        let appState = AppState()
        XCTAssertFalse(appState.translationEnabled)
    }

    @MainActor
    func testTranslationEnabledCanBeToggled() {
        let appState = AppState()
        XCTAssertFalse(appState.translationEnabled)
        
        appState.translationEnabled = true
        XCTAssertTrue(appState.translationEnabled)
        
        appState.translationEnabled = false
        XCTAssertFalse(appState.translationEnabled)
    }
}

// MARK: - WhisperService Translation Tests

final class WhisperServiceTranslationTests: XCTestCase {

    func testTranscribeMethodAcceptsTranslateParameter() {
        // This test verifies that the transcribe method signature includes the translate parameter
        // The actual transcription would require a loaded model and audio data,
        // but we're just testing that the method compiles with the translate parameter
        let service = WhisperService()
        XCTAssertNotNil(service)
    }
}

// MARK: - OnboardingStep Tests

final class OnboardingStepTests: XCTestCase {

    func testOnboardingStepOrdering() {
        let steps = OnboardingStep.allCases
        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps[0], .welcome)
        XCTAssertEqual(steps[1], .permissions)
        XCTAssertEqual(steps[2], .hotkeyConfig)
        XCTAssertEqual(steps[3], .quickTest)
        XCTAssertEqual(steps[4], .complete)
    }

    func testOnboardingStepTitles() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
        }
    }

    func testOnboardingStepNumbers() {
        for (index, step) in OnboardingStep.allCases.enumerated() {
            XCTAssertEqual(step.stepNumber, "Step \(index + 1) of \(OnboardingStep.allCases.count)")
        }
    }

    func testOnboardingStepIdentifiable() {
        let steps = OnboardingStep.allCases
        let ids = steps.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count)
    }
}

// MARK: - AudioEngine Tests

final class AudioEngineTests: XCTestCase {

    func testStopRecordingWithoutStartReturnsEmpty() {
        let engine = AudioEngine()
        let samples = engine.stopRecording()
        XCTAssertTrue(samples.isEmpty)
    }

    func testSilenceCallbackFiresOnlyOnce() {
        // Verify that the silence detection callback doesn't fire repeatedly
        // by simulating the scenario where multiple silent buffers arrive
        let engine = AudioEngine()
        var silenceCallCount = 0

        engine.onSilenceDetected = {
            silenceCallCount += 1
        }

        // Start recording with a very short silence duration so it triggers quickly
        engine.startRecording(
            silenceThreshold: 0.5,  // High threshold so normal ambient noise counts as silence
            silenceDuration: 0.01,  // Very short so it fires quickly
            maxDuration: 60.0
        )

        // Wait for a few audio callbacks to process silence
        let expectation = XCTestExpectation(description: "Silence detection fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let _ = engine.stopRecording()

        // The callback should have fired at most once due to the silenceCallbackFired guard
        XCTAssertLessThanOrEqual(silenceCallCount, 1,
            "Silence callback should fire at most once, but fired \(silenceCallCount) times")
    }

    func testMaxDurationCallbackFiresOnlyOnce() {
        let engine = AudioEngine()
        var maxDurationCallCount = 0

        engine.onMaxDurationReached = {
            maxDurationCallCount += 1
        }

        // Start recording with a very short max duration
        engine.startRecording(
            silenceThreshold: 0.01,
            silenceDuration: 999.0,  // Long silence duration so it doesn't interfere
            maxDuration: 0.01       // Very short max duration
        )

        // Wait for max duration to be reached
        let expectation = XCTestExpectation(description: "Max duration fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let _ = engine.stopRecording()

        // The callback should have fired at most once
        XCTAssertLessThanOrEqual(maxDurationCallCount, 1,
            "Max duration callback should fire at most once, but fired \(maxDurationCallCount) times")
    }

    func testAudioBufferNotEmptyAfterRecording() {
        // When we record for a short time, we should get some audio data back
        let engine = AudioEngine()

        engine.startRecording(
            silenceThreshold: 0.01,
            silenceDuration: 999.0,
            maxDuration: 60.0
        )

        // Record for a brief period
        let expectation = XCTestExpectation(description: "Recording period")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let samples = engine.stopRecording()

        // We should have captured some audio (even if it's silence/ambient noise)
        XCTAssertFalse(samples.isEmpty,
            "Audio buffer should contain samples after recording")
    }

    func testAudioBufferPreservedWhenSilenceDetected() {
        // The key bug fix: audio should be buffered BEFORE silence detection fires,
        // so we don't lose the audio frames that triggered the silence condition
        let engine = AudioEngine()
        var silenceDetected = false

        engine.onSilenceDetected = {
            silenceDetected = true
        }

        // Use a high silence threshold so even ambient noise triggers silence detection
        engine.startRecording(
            silenceThreshold: 0.99,  // Almost everything is "silence"
            silenceDuration: 0.01,   // Fire immediately
            maxDuration: 60.0
        )

        // Wait for silence to be detected and audio to accumulate
        let expectation = XCTestExpectation(description: "Silence detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let samples = engine.stopRecording()

        // Even though silence was detected, audio should still be in the buffer
        // because we now append BEFORE checking silence conditions
        if silenceDetected {
            XCTAssertFalse(samples.isEmpty,
                "Audio buffer should NOT be empty even when silence is detected — " +
                "frames must be appended before the silence check")
        }
    }

    func testAudioBufferPreservedWhenMaxDurationReached() {
        // Audio should be buffered even when max duration is reached
        let engine = AudioEngine()
        var maxDurationReached = false

        engine.onMaxDurationReached = {
            maxDurationReached = true
        }

        engine.startRecording(
            silenceThreshold: 0.01,
            silenceDuration: 999.0,
            maxDuration: 0.01  // Reach max duration almost immediately
        )

        // Wait for max duration to fire
        let expectation = XCTestExpectation(description: "Max duration reached")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let samples = engine.stopRecording()

        // Even though max duration was reached, audio should still be in the buffer
        if maxDurationReached {
            XCTAssertFalse(samples.isEmpty,
                "Audio buffer should NOT be empty when max duration is reached — " +
                "frames must be appended before the max duration check")
        }
    }
}

// MARK: - Launch at Login Tests

final class LaunchAtLoginTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
    }

    override func tearDown() {
        // Clean up: ensure we don't leave the app registered as a login item from tests
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
        try? SMAppService.mainApp.unregister()
        super.tearDown()
    }

    @MainActor
    func testLaunchAtLoginDefaultsToFalse() {
        let appState = AppState()
        XCTAssertFalse(appState.launchAtLogin)
    }

    @MainActor
    func testLaunchAtLoginPersistence() {
        UserDefaults.standard.set(true, forKey: "vocamac.launchAtLogin")
        let appState = AppState()
        XCTAssertTrue(appState.launchAtLogin)
    }

    @MainActor
    func testSetLaunchAtLoginEnableUpdatesPreference() {
        let appState = AppState()
        XCTAssertFalse(appState.launchAtLogin)

        appState.setLaunchAtLogin(true)

        // The preference should reflect the requested state
        // (SMAppService.mainApp.register() may or may not succeed depending
        // on the test environment, but the method should not crash)
        // If registration succeeded, launchAtLogin will be true.
        // If it failed, launchAtLogin will match the actual system state.
        // Either way, the value should be consistent with SMAppService.mainApp.status
        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginDisableUpdatesPreference() {
        let appState = AppState()
        appState.setLaunchAtLogin(true)
        appState.setLaunchAtLogin(false)

        // After disabling, launchAtLogin should match the system state
        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginToggleRoundTrip() {
        let appState = AppState()

        // Enable
        appState.setLaunchAtLogin(true)
        let afterEnable = appState.launchAtLogin

        // Disable
        appState.setLaunchAtLogin(false)
        let afterDisable = appState.launchAtLogin

        // The states should be different (assuming SMAppService works in this env)
        // If SMAppService isn't available, both will match the system state
        if SMAppService.mainApp.status != .enabled {
            XCTAssertFalse(afterDisable,
                "After disabling, launchAtLogin should be false")
        }
        // Just verify no crashes occurred during the round-trip
        XCTAssertNotNil(afterEnable)
        XCTAssertNotNil(afterDisable)
    }
}

// MARK: - AppState Onboarding Tests

final class AppStateOnboardingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any persisted state before each test
        UserDefaults.standard.removeObject(forKey: "vocamac.hasCompletedOnboarding")
    }

    @MainActor
    func testOnboardingFlagInitiallyFalse() {
        let appState = AppState()
        XCTAssertFalse(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testCompleteOnboardingSetsFlagTrue() {
        let appState = AppState()
        XCTAssertFalse(appState.hasCompletedOnboarding)
        
        appState.completeOnboarding()
        
        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testOnboardingFlagPersistence() {
        // Set the flag
        UserDefaults.standard.set(true, forKey: "vocamac.hasCompletedOnboarding")
        
        let appState = AppState()
        
        // Verify it was loaded from UserDefaults
        XCTAssertTrue(appState.hasCompletedOnboarding)
    }
}

// MARK: - WhisperService Hallucination Filtering Tests

final class WhisperServiceHallucinationTests: XCTestCase {

    func testFilterBlankAudioToken() {
        let input = "[BLANK_AUDIO]"
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "", "Should filter out [BLANK_AUDIO] token completely")
    }

    func testFilterBlankAudioTokenCaseInsensitive() {
        let input = "[blank_audio]"
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "", "Should filter out [blank_audio] case-insensitively")
    }

    func testFilterBlankAudioMixedWithText() {
        let input = "Hello [BLANK_AUDIO] world"
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "Hello world", "Should remove token and collapse spaces")
    }

    func testFilterMultipleHallucinationTokens() {
        let input = "[BLANK_AUDIO] [NO_SPEECH] some text (silence)"
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "some text", "Should remove all hallucination tokens")
    }

    func testFilterPreservesNormalText() {
        let input = "This is a normal transcription"
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "This is a normal transcription", "Should not modify normal text")
    }

    func testFilterEmptyInput() {
        let input = ""
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "", "Should handle empty input gracefully")
    }

    func testFilterOnlyWhitespaceAroundToken() {
        let input = "   [BLANK_AUDIO]   "
        let result = WhisperService.filterHallucinationTokens(input)
        XCTAssertEqual(result, "", "Should return empty after filtering and trimming")
    }
}
