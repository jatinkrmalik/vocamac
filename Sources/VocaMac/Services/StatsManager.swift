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

        let dateKey = dayKey(for: transcription.timestamp)

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

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func updateStreaks(currentDate: Date) {
        guard let lastDate = stats.lastUsageDate else {
            // First time usage
            stats.currentStreak = 1
            stats.bestStreak = 1
            return
        }

        let lastDay = calendar.startOfDay(for: lastDate)
        let currentDay = calendar.startOfDay(for: currentDate)
        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: currentDay).day

        switch daysBetween {
        case 0:
            // Already used on this calendar day, streak remains same
            break
        case 1:
            // Continuation of streak
            stats.currentStreak += 1
        default:
            // Streak broken or older transcription recorded out of order
            stats.currentStreak = 1
        }

        if stats.currentStreak > stats.bestStreak {
            stats.bestStreak = stats.currentStreak
        }
    }
}
