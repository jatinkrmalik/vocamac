// StatsManager.swift
// VocaMac
//
// Manages the persistence and updating of user statistics.

import Foundation
import Combine

@MainActor
class StatsManager: StatsManaging, ObservableObject {
    @Published private(set) var stats: UserStats = UserStats()

    var objectWillChangePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    private let fileManager = FileManager.default
    private let statsFileURL: URL
    private let calendar: Calendar

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(statsFileURL: URL? = nil, calendar: Calendar = .current) {
        if let statsFileURL {
            self.statsFileURL = statsFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let vMacDir = appSupport.appendingPathComponent("VocaMac", isDirectory: true)

            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: vMacDir.path) {
                try? FileManager.default.createDirectory(at: vMacDir, withIntermediateDirectories: true)
            }
            self.statsFileURL = vMacDir.appendingPathComponent("stats.json")
        }
        self.calendar = calendar
        loadStats()
    }

    private func loadStats() {
        do {
            if fileManager.fileExists(atPath: statsFileURL.path) {
                let data = try Data(contentsOf: statsFileURL)
                stats = try JSONDecoder().decode(UserStats.self, from: data)
                VocaLogger.debug(.general, "User stats loaded from disk")
            } else {
                VocaLogger.info(.general, "No stats file found, starting fresh")
            }
        } catch {
            VocaLogger.error(.general, "Failed to load stats: \(error.localizedDescription)")
        }
    }

    private func saveStats() {
        do {
            let data = try JSONEncoder().encode(stats)
            try data.write(to: statsFileURL, options: .atomic)
            VocaLogger.debug(.general, "User stats saved to disk")
        } catch {
            VocaLogger.error(.general, "Failed to save stats: \(error.localizedDescription)")
        }
    }

    func recordTranscription(_ transcription: VocaTranscription) {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Estimate word count
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        let dateKey = Self.dateFormatter.string(from: transcription.timestamp)

        // Update basic counts
        stats.totalWords += words
        stats.totalTranscriptions += 1
        stats.totalAudioDurationSeconds += transcription.audioLengthSeconds

        // Update daily stats
        stats.dailyWordCounts[dateKey, default: 0] += words
        stats.dailyDurationSeconds[dateKey, default: 0] += transcription.audioLengthSeconds

        // Update streaks
        updateStreaks(currentDate: transcription.timestamp)

        stats.lastUsageDate = transcription.timestamp

        saveStats()
    }

    func resetStats() {
        stats = UserStats()
        saveStats()
    }

    private func updateStreaks(currentDate: Date) {
        guard let lastDate = stats.lastUsageDate else {
            // First time usage
            stats.currentStreak = 1
            stats.bestStreak = 1
            return
        }

        // Check if last usage was yesterday
        if calendar.isDateInYesterday(lastDate) {
            // Continuation of streak
            if !calendar.isDate(lastDate, inSameDayAs: currentDate) {
                stats.currentStreak += 1
            }
        } else if calendar.isDate(lastDate, inSameDayAs: currentDate) {
            // Already used today, streak remains same
        } else {
            // Streak broken
            stats.currentStreak = 1
        }

        if stats.currentStreak > stats.bestStreak {
            stats.bestStreak = stats.currentStreak
        }
    }
}
