// CursorOverlayTests.swift
// VocaMac
//
// Tests for CursorOverlayManager, IndicatorPhase, and MicIndicatorViewModel.

import XCTest
@testable import VocaMac

// MARK: - IndicatorPhase Tests

final class IndicatorPhaseTests: XCTestCase {

    func testAllPhasesExist() {
        // Verify all indicator phases can be instantiated
        let phases: [IndicatorPhase] = [.recording, .processing, .idle]
        XCTAssertEqual(phases.count, 3, "Should have exactly 3 indicator phases")
    }
}

// MARK: - MicIndicatorViewModel Tests

@MainActor
final class MicIndicatorViewModelTests: XCTestCase {

    func testDefaultState() {
        let viewModel = MicIndicatorViewModel()

        XCTAssertEqual(viewModel.phase, .idle, "Default phase should be idle")
        XCTAssertEqual(viewModel.audioLevel, 0.0, "Default audio level should be 0")
    }

    func testPhaseTransitions() {
        let viewModel = MicIndicatorViewModel()

        viewModel.phase = .recording
        XCTAssertEqual(viewModel.phase, .recording)

        viewModel.phase = .processing
        XCTAssertEqual(viewModel.phase, .processing)

        viewModel.phase = .idle
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testAudioLevelUpdates() {
        let viewModel = MicIndicatorViewModel()

        viewModel.audioLevel = 0.5
        XCTAssertEqual(viewModel.audioLevel, 0.5, accuracy: 0.001)

        viewModel.audioLevel = 1.0
        XCTAssertEqual(viewModel.audioLevel, 1.0, accuracy: 0.001)

        viewModel.audioLevel = 0.0
        XCTAssertEqual(viewModel.audioLevel, 0.0, accuracy: 0.001)
    }
}

// MARK: - CursorOverlayManager Tests

@MainActor
final class CursorOverlayManagerTests: XCTestCase {

    func testInitialState() {
        let manager = CursorOverlayManager()
        XCTAssertNotNil(manager)
    }

    func testHideIsIdempotent() {
        let manager = CursorOverlayManager()
        manager.hide()
        manager.hide()
        manager.hide()
    }

    func testTransitionToProcessingWithoutShow() {
        let manager = CursorOverlayManager()
        manager.transitionToProcessing()
    }

    func testUpdateAudioLevelWithoutShow() {
        let manager = CursorOverlayManager()
        manager.updateAudioLevel(0.5)
        manager.updateAudioLevel(0.0)
        manager.updateAudioLevel(1.0)
    }
}
