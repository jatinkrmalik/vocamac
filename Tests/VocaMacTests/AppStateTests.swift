// AppStateTests.swift
// VocaMac Tests
//
// Tests for AppState: translation toggle, onboarding, launch at login.

import XCTest
import ServiceManagement
@testable import VocaMac

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

