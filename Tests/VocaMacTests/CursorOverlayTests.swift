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

// MARK: - PositionSource Tests

final class PositionSourceTests: XCTestCase {

    func testAllSourcesExist() {
        let sources: [CursorOverlayManager.PositionSource] = [
            .caret, .focusedElement, .focusedWindow, .mouseCursor
        ]
        XCTAssertEqual(sources.count, 4, "Should have exactly 4 position sources")
    }

    func testRawValues() {
        XCTAssertEqual(CursorOverlayManager.PositionSource.caret.rawValue, "caret")
        XCTAssertEqual(CursorOverlayManager.PositionSource.focusedElement.rawValue, "focused_element")
        XCTAssertEqual(CursorOverlayManager.PositionSource.focusedWindow.rawValue, "focused_window")
        XCTAssertEqual(CursorOverlayManager.PositionSource.mouseCursor.rawValue, "mouse_cursor")
    }
}

// MARK: - CursorOverlayManager Tests

@MainActor
final class CursorOverlayManagerTests: XCTestCase {

    func testInitialState() {
        let manager = CursorOverlayManager()
        // Should initialize without crashing
        XCTAssertNotNil(manager)
    }

    func testHideIsIdempotent() {
        let manager = CursorOverlayManager()

        // Calling hide when not shown should not crash
        manager.hide()
        manager.hide()
        manager.hide()
    }

    func testTransitionToProcessingWithoutShow() {
        let manager = CursorOverlayManager()

        // Should be safe to call without show() first
        manager.transitionToProcessing()
    }

    func testUpdateAudioLevelWithoutShow() {
        let manager = CursorOverlayManager()

        // Should be safe to update audio level when not visible
        manager.updateAudioLevel(0.5)
        manager.updateAudioLevel(0.0)
        manager.updateAudioLevel(1.0)
    }

    func testDetectIndicatorPositionReturnsResult() {
        let manager = CursorOverlayManager()

        // In a CI/test environment without accessibility permissions,
        // this should gracefully fall back to mouse cursor position
        let result = manager.detectIndicatorPosition()

        // The result should always produce a valid position
        XCTAssertFalse(result.point.x.isNaN, "X coordinate should not be NaN")
        XCTAssertFalse(result.point.y.isNaN, "Y coordinate should not be NaN")

        // Without accessibility permissions in test, we expect mouse cursor fallback
        // (but don't assert the exact source since it depends on system state)
        let validSources: [CursorOverlayManager.PositionSource] = [
            .caret, .focusedElement, .focusedWindow, .mouseCursor
        ]
        XCTAssertTrue(
            validSources.contains(result.source),
            "Position source should be one of the known sources"
        )
    }

    func testPositionResultStoresValues() {
        let point = NSPoint(x: 100, y: 200)
        let result = CursorOverlayManager.PositionResult(
            point: point,
            source: .focusedElement
        )

        XCTAssertEqual(result.point.x, 100)
        XCTAssertEqual(result.point.y, 200)
        XCTAssertEqual(result.source, .focusedElement)
    }
}
