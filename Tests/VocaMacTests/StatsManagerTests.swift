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
    func testDailyBucketsUseInjectedCalendarTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        statsManager = StatsManager(statsFileURL: tempFileURL, calendar: calendar)

        let nearMidnightUTC = Date(timeIntervalSince1970: 1_704_060_000) // 2023-12-31 22:00:00 UTC, 2024-01-01 in GMT+2
        let transcription = VocaTranscription(
            text: "local day",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: nearMidnightUTC
        )

        statsManager.recordTranscription(transcription)

        XCTAssertEqual(statsManager.stats.dailyWordCounts["2024-01-01"], 2)
        XCTAssertNil(statsManager.stats.dailyWordCounts["2023-12-31"])
    }

    @MainActor
    func testStreakUsesTranscriptionDateRatherThanCurrentDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        statsManager = StatsManager(statsFileURL: tempFileURL, calendar: calendar)

        let firstDay = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01 00:00:00 UTC
        let secondDay = Date(timeIntervalSince1970: 946_771_200) // 2000-01-02 00:00:00 UTC

        statsManager.recordTranscription(VocaTranscription(
            text: "first day",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: firstDay
        ))
        statsManager.recordTranscription(VocaTranscription(
            text: "second day",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: secondDay
        ))

        XCTAssertEqual(statsManager.stats.currentStreak, 2)
        XCTAssertEqual(statsManager.stats.bestStreak, 2)
    }

    @MainActor
    func testSameDayTranscriptionsDoNotIncrementStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        statsManager = StatsManager(statsFileURL: tempFileURL, calendar: calendar)

        let first = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01 00:00:00 UTC
        let second = Date(timeIntervalSince1970: 946_728_000) // 2000-01-01 12:00:00 UTC

        statsManager.recordTranscription(VocaTranscription(
            text: "morning words",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: first
        ))
        statsManager.recordTranscription(VocaTranscription(
            text: "afternoon words",
            duration: 1.0,
            detectedLanguage: "en",
            audioLengthSeconds: 1.0,
            modelUsed: .tiny,
            timestamp: second
        ))

        XCTAssertEqual(statsManager.stats.currentStreak, 1)
        XCTAssertEqual(statsManager.stats.bestStreak, 1)
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
