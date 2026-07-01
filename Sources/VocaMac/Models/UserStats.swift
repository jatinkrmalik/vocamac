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

    /// Calculated average Words Per Minute (WPM).
    /// Note: This is "words-per-minute-of-audio", dividing total words by total audio duration.
    var averageWPM: Double {
        guard totalAudioDurationSeconds > 0 else { return 0 }
        let minutes = totalAudioDurationSeconds / 60.0
        return Double(totalWords) / minutes
    }
}

extension UserStats {
    /// Decode leniently so evolving the schema never wipes a user's saved stats:
    /// any key missing from an older `stats.json` falls back to its default.
    /// (Synthesized `Codable` requires every non-optional key, so adding a field
    /// later would otherwise fail decoding and silently reset all history.)
    /// Declared in an extension to keep the memberwise `UserStats()` initializer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        totalWords = try container.decodeIfPresent(Int.self, forKey: .totalWords) ?? totalWords
        totalTranscriptions = try container.decodeIfPresent(Int.self, forKey: .totalTranscriptions) ?? totalTranscriptions
        totalAudioDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .totalAudioDurationSeconds) ?? totalAudioDurationSeconds
        lastUsageDate = try container.decodeIfPresent(Date.self, forKey: .lastUsageDate)
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? currentStreak
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? bestStreak
        dailyWordCounts = try container.decodeIfPresent([String: Int].self, forKey: .dailyWordCounts) ?? dailyWordCounts
    }
}
