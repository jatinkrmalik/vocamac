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
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.translationEnabled)
    }

    @MainActor
    func testTranslationEnabledCanBeToggled() {
        let (appState, _) = AppState.makeTestState()
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
        UserDefaults.standard.removeObject(forKey: "vocamac.launchAtLogin")
        super.tearDown()
    }

    @MainActor
    func testLaunchAtLoginDefaultsToFalse() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.launchAtLogin)
    }

    @MainActor
    func testLaunchAtLoginPersistence() {
        UserDefaults.standard.set(true, forKey: "vocamac.launchAtLogin")
        let (appState, _) = AppState.makeTestState()
        XCTAssertTrue(appState.launchAtLogin)
    }

    @MainActor
    func testSetLaunchAtLoginEnableUpdatesPreference() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.launchAtLogin)

        appState.setLaunchAtLogin(true)

        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginDisableUpdatesPreference() {
        let (appState, _) = AppState.makeTestState()
        appState.setLaunchAtLogin(true)
        appState.setLaunchAtLogin(false)

        let expected = SMAppService.mainApp.status == .enabled
        XCTAssertEqual(appState.launchAtLogin, expected)
    }

    @MainActor
    func testSetLaunchAtLoginToggleRoundTrip() {
        let (appState, _) = AppState.makeTestState()

        appState.setLaunchAtLogin(true)
        let afterEnable = appState.launchAtLogin

        appState.setLaunchAtLogin(false)
        let afterDisable = appState.launchAtLogin

        if SMAppService.mainApp.status != .enabled {
            XCTAssertFalse(afterDisable,
                "After disabling, launchAtLogin should be false")
        }
        XCTAssertNotNil(afterEnable)
        XCTAssertNotNil(afterDisable)
    }
}

// MARK: - AppState Onboarding Tests

final class AppStateOnboardingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "vocamac.hasCompletedOnboarding")
    }

    @MainActor
    func testOnboardingFlagInitiallyFalse() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testCompleteOnboardingSetsFlagTrue() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertFalse(appState.hasCompletedOnboarding)

        appState.completeOnboarding()

        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testOnboardingFlagPersistence() {
        UserDefaults.standard.set(true, forKey: "vocamac.hasCompletedOnboarding")

        let (appState, _) = AppState.makeTestState()

        XCTAssertTrue(appState.hasCompletedOnboarding)
    }

    @MainActor
    func testPerformStartupInstallsBundledTinyModelBeforeDownload() async {
        let (appState, mocks) = AppState.makeTestState()
        mocks.modelManager.bundledModels = [.tiny]
        appState.selectedModelSize = ModelSize.tiny.rawValue

        await appState.performStartup()

        XCTAssertEqual(mocks.modelManager.installedBundledModels, [.tiny])
        XCTAssertEqual(mocks.modelManager.ensuredTokenizerSizes, [.tiny])
        XCTAssertEqual(mocks.whisperService.loadedModelName, "openai_whisper-tiny")
    }
}
