// UserStats.swift
// VocaMac
//
// Data model for tracking user usage statistics.

import Foundation

struct UserStats: Codable {
    /// Total number of words transcribed across all sessions
    var totalWords: Int = 0

    /// Total number of successful transcriptions performed
    var totalTranscriptions: Int = 0

    /// Total duration of audio recorded in seconds
    var totalAudioDurationSeconds: Double = 0

    /// Date of the most recent transcription
    var lastUsageDate: Date?

    /// Current consecutive days of usage
    var currentStreak: Int = 0

    /// Highest consecutive days of usage recorded
    var bestStreak: Int = 0

    /// Daily word counts to calculate trends and streaks
    /// Key is date string in "yyyy-MM-dd" format
    var dailyWordCounts: [String: Int] = [:]

    /// Daily duration to calculate WPM history
    var dailyDurationSeconds: [String: Double] = [:]

    /// Calculated average Words Per Minute (WPM).
    /// Note: This is "words-per-minute-of-audio", dividing total words by total audio duration.
    var averageWPM: Double {
        guard totalAudioDurationSeconds > 0 else { return 0 }
        let minutes = totalAudioDurationSeconds / 60.0
        return Double(totalWords) / minutes
    }
}
