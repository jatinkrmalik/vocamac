// StatsManagerTests.swift
// VocaMac Tests
//
// Tests for StatsManager logic including word counting, streaks, and WPM.

import XCTest
import Combine
@testable import VocaMac

final class StatsManagerTests: XCTestCase {
    var statsManager: StatsManager!
    var cancellables: Set<AnyCancellable>!
    var tempFileURL: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("stats_test_\(UUID().uuidString).json")
        statsManager = StatsManager(statsFileURL: tempFileURL)
        cancellables = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    @MainActor
    func testInitialStatsAreEmpty() {
        XCTAssertEqual(statsManager.stats.totalWords, 0)
        XCTAssertEqual(statsManager.stats.totalTranscriptions, 0)
        XCTAssertEqual(statsManager.stats.currentStreak, 0)
    }

    @MainActor
    func testRecordingTranscriptionUpdatesCounts() {
        let transcription = VocaTranscription(
            text: "Hello world this is a test.", // 6 words
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 10.0,
            modelUsed: .tiny
        )

        statsManager.recordTranscription(transcription)

        XCTAssertEqual(statsManager.stats.totalWords, 6)
        XCTAssertEqual(statsManager.stats.totalTranscriptions, 1)
        XCTAssertEqual(statsManager.stats.totalAudioDurationSeconds, 10.0)
    }

    @MainActor
    func testWPMCalculation() {
        let transcription = VocaTranscription(
            text: "One two three four five.", // 5 words
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 30.0, // 0.5 minutes
            modelUsed: .tiny
        )

        statsManager.recordTranscription(transcription)

        // WPM = 5 words / 0.5 minutes = 10 WPM
        XCTAssertEqual(statsManager.stats.averageWPM, 10.0)
    }

    @MainActor
    func testStreakIncrementsOnNewDay() {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // 1. Record for yesterday
        let t1 = VocaTranscription(
            text: "Yesterday transcription",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: yesterday
        )
        statsManager.recordTranscription(t1)
        XCTAssertEqual(statsManager.stats.currentStreak, 1)

        // 2. Record for today
        let t2 = VocaTranscription(
            text: "Today transcription",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: today
        )
        statsManager.recordTranscription(t2)
        XCTAssertEqual(statsManager.stats.currentStreak, 2, "Streak should increment on consecutive days")
        XCTAssertEqual(statsManager.stats.bestStreak, 2)
    }

    @MainActor
    func testStreakBrokenAfterGap() {
        let calendar = Calendar.current
        let today = Date()
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        // 1. Record for 3 days ago
        let t1 = VocaTranscription(
            text: "Old transcription",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: threeDaysAgo
        )
        statsManager.recordTranscription(t1)
        XCTAssertEqual(statsManager.stats.currentStreak, 1)

        // 2. Record for today (2 day gap)
        let t2 = VocaTranscription(
            text: "Today transcription",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: today
        )
        statsManager.recordTranscription(t2)
        XCTAssertEqual(statsManager.stats.currentStreak, 1, "Streak should reset after a gap")
    }

    @MainActor
    func testResetStats() {
        let transcription = VocaTranscription(text: "Test", duration: 1.0, detectedLanguage: "en", audioLengthSeconds: 1.0, modelUsed: .tiny)
        statsManager.recordTranscription(transcription)
        XCTAssertEqual(statsManager.stats.totalTranscriptions, 1)

        statsManager.resetStats()
        XCTAssertEqual(statsManager.stats.totalTranscriptions, 0)
        XCTAssertEqual(statsManager.stats.totalWords, 0)
    }
}
