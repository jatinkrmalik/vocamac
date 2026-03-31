// ServiceTests.swift
// VocaMac Tests
//
// Tests for services: KeyCodeReference, TextInjector, SoundManager, AudioEngine.

import XCTest
@testable import VocaMac

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

