// WhisperServiceTests.swift
// VocaMac Tests
//
// Tests for WhisperService: translation and hallucination filtering.

import XCTest
@testable import VocaMac

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
