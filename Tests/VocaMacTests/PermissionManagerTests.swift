// PermissionManagerTests.swift
// VocaMac
//
// Tests for the PermissionManager service.

import XCTest
@testable import VocaMac

// MARK: - PermissionStatus Tests

final class PermissionStatusTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(PermissionStatus.notDetermined.rawValue, "notDetermined")
        XCTAssertEqual(PermissionStatus.granted.rawValue, "granted")
        XCTAssertEqual(PermissionStatus.denied.rawValue, "denied")
    }

    func testAllCasesAreDistinct() {
        let cases: [PermissionStatus] = [.notDetermined, .granted, .denied]
        let unique = Set(cases.map { $0.rawValue })
        XCTAssertEqual(unique.count, 3, "All PermissionStatus cases should have unique raw values")
    }

    func testEquality() {
        XCTAssertEqual(PermissionStatus.granted, PermissionStatus.granted)
        XCTAssertNotEqual(PermissionStatus.granted, PermissionStatus.denied)
        XCTAssertNotEqual(PermissionStatus.notDetermined, PermissionStatus.granted)
    }
}

// MARK: - PermissionManager Tests

@MainActor
final class PermissionManagerTests: XCTestCase {

    func testInitialPermissionStates() {
        let audioEngine = AudioEngine()
        let hotKeyManager = HotKeyManager()
        let manager = PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)

        XCTAssertEqual(manager.micPermission, .notDetermined)
        XCTAssertEqual(manager.accessibilityPermission, .notDetermined)
        XCTAssertEqual(manager.inputMonitoringPermission, .notDetermined)
    }

    func testAllPermissionsGrantedWhenNoneGranted() {
        let audioEngine = AudioEngine()
        let hotKeyManager = HotKeyManager()
        let manager = PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)

        XCTAssertFalse(manager.allPermissionsGranted,
                       "allPermissionsGranted should be false when no permissions are granted")
    }

    func testCheckPermissionsUpdatesState() {
        let audioEngine = AudioEngine()
        let hotKeyManager = HotKeyManager()
        let manager = PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)

        // After checking, permissions should no longer be .notDetermined
        // (they'll be either .granted or .denied depending on system state)
        manager.checkPermissions()

        // Mic permission should transition from notDetermined
        // (In CI/test environment it will be denied since there's no mic access)
        XCTAssertNotEqual(manager.micPermission, .notDetermined,
                         "Mic permission should be determined after checking")
    }

    func testStopPermissionPollingIsIdempotent() {
        let audioEngine = AudioEngine()
        let hotKeyManager = HotKeyManager()
        let manager = PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)

        // Calling stopPermissionPolling when no timer is running should not crash
        manager.stopPermissionPolling()
        manager.stopPermissionPolling()
    }

    func testOnAllPermissionsGrantedCallbackCanBeSet() {
        let audioEngine = AudioEngine()
        let hotKeyManager = HotKeyManager()
        let manager = PermissionManager(audioEngine: audioEngine, hotKeyManager: hotKeyManager)

        var callbackCalled = false
        manager.onAllPermissionsGranted = {
            callbackCalled = true
        }

        // Verify callback was stored (we can't trigger it without granting
        // all permissions, but we verify the property accepts a closure)
        XCTAssertNotNil(manager.onAllPermissionsGranted)
        manager.onAllPermissionsGranted?()
        XCTAssertTrue(callbackCalled, "Callback should be invokable")
    }
}
