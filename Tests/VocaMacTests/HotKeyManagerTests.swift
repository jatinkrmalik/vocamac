// HotKeyManagerTests.swift
// VocaMac
//
// Tests for HotKeyManager configuration and state logic.

import XCTest
@testable import VocaMac

// MARK: - HotKeyManager Configuration Tests

final class HotKeyManagerConfigurationTests: XCTestCase {

    func testDefaultState() {
        let manager = HotKeyManager()

        XCTAssertFalse(manager.isListening, "Should not be listening initially")
        XCTAssertNil(manager.activeEventTap, "Should have no event tap initially")
        XCTAssertNil(manager.eventTap, "Should have no event tap initially")
    }

    func testUpdateConfigurationKeyCode() {
        let manager = HotKeyManager()

        manager.updateConfiguration(keyCode: 58) // Left Option
        // Configuration should be accepted without crashing
        // (keyCode is private, but the method should not throw)
    }

    func testUpdateConfigurationMode() {
        let manager = HotKeyManager()

        manager.updateConfiguration(mode: .doubleTapToggle)
        manager.updateConfiguration(mode: .pushToTalk)
        // Both modes should be accepted without issues
    }

    func testUpdateConfigurationDoubleTapThreshold() {
        let manager = HotKeyManager()

        manager.updateConfiguration(doubleTapThreshold: 0.3)
        manager.updateConfiguration(doubleTapThreshold: 0.5)
        manager.updateConfiguration(doubleTapThreshold: 1.0)
    }

    func testUpdateConfigurationSafetyTimeout() {
        let manager = HotKeyManager()

        manager.updateConfiguration(safetyTimeout: 30.0)
        manager.updateConfiguration(safetyTimeout: 65.0)
    }

    func testUpdateConfigurationMultipleParams() {
        let manager = HotKeyManager()

        // Should accept multiple parameters at once
        manager.updateConfiguration(
            keyCode: 55,
            mode: .doubleTapToggle,
            doubleTapThreshold: 0.5,
            safetyTimeout: 120.0
        )
    }

    func testUpdateConfigurationNilParams() {
        let manager = HotKeyManager()

        // Nil parameters should leave existing values unchanged
        manager.updateConfiguration(keyCode: nil, mode: nil, doubleTapThreshold: nil, safetyTimeout: nil)
        // Should not crash
    }

    func testCallbacksInitiallyNil() {
        let manager = HotKeyManager()

        XCTAssertNil(manager.onRecordingStart, "onRecordingStart should be nil initially")
        XCTAssertNil(manager.onRecordingStop, "onRecordingStop should be nil initially")
    }

    func testCallbacksCanBeSet() {
        let manager = HotKeyManager()
        var startCalled = false
        var stopCalled = false

        manager.onRecordingStart = { startCalled = true }
        manager.onRecordingStop = { stopCalled = true }

        manager.onRecordingStart?()
        manager.onRecordingStop?()

        XCTAssertTrue(startCalled, "Start callback should be invokable")
        XCTAssertTrue(stopCalled, "Stop callback should be invokable")
    }

    func testStopListeningWithoutStarting() {
        let manager = HotKeyManager()

        // Should not crash when stopping without having started
        manager.stopListening()
        XCTAssertFalse(manager.isListening)
    }

    func testStopListeningIdempotent() {
        let manager = HotKeyManager()

        manager.stopListening()
        manager.stopListening()
        manager.stopListening()
        XCTAssertFalse(manager.isListening)
    }
}
