// SoundManager.swift
// VocaMac
//
// Plays audio feedback sounds for recording start/stop events.
// Uses macOS system sounds for soft, pleasing audio cues.

import Foundation
import AppKit

final class SoundManager: NSObject, NSSoundDelegate, @unchecked Sendable {

    // MARK: - Sound Names

    /// Soft pop sound for recording start
    private let startSoundName = "Pop"

    /// Hollow bottle sound for recording stop
    private let stopSoundName = "Bottle"

    // MARK: - Properties

    /// Volume for sound effects (0.0 to 1.0)
    var volume: Float = 0.5

    /// Lock for thread-safe access to continuation
    private let continuationLock = NSLock()

    /// Continuation for async sound playback completion
    private var soundCompletionContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Public API

    /// Play the recording-started sound (synchronous, fire-and-forget)
    func playStartSound() {
        playSystemSound(startSoundName)
    }

    /// Play the recording-started sound and wait for completion
    /// Ensures the sound finishes before returning, preventing mic capture of the sound.
    /// - Throws: May timeout if sound is stuck
    func playStartSoundAsync() async {
        await playSystemSoundAsync(startSoundName)
    }

    /// Play the recording-stopped sound (synchronous, fire-and-forget)
    func playStopSound() {
        playSystemSound(stopSoundName)
    }

    /// Play the recording-stopped sound and wait for completion
    /// Ensures the sound finishes before returning.
    /// - Throws: May timeout if sound is stuck
    func playStopSoundAsync() async {
        await playSystemSoundAsync(stopSoundName)
    }

    // MARK: - Private

    /// Play a macOS system sound by name (fire-and-forget)
    private func playSystemSound(_ name: String) {
        let soundPath = "/System/Library/Sounds/\(name).aiff"
        guard let sound = NSSound(contentsOfFile: soundPath, byReference: true) else {
            VocaLogger.warning(.soundManager, "Could not load system sound: \(name)")
            return
        }
        sound.volume = volume
        sound.play()
    }

    /// Play a system sound and wait for completion using async/await
    /// Uses NSSoundDelegate callback to detect when playback finishes.
    /// Includes a 1-second timeout to prevent stuck sounds from blocking recording.
    /// - Parameter name: The system sound name to play (e.g., "Pop", "Bottle")
    private func playSystemSoundAsync(_ name: String) async {
        let soundPath = "/System/Library/Sounds/\(name).aiff"
        guard let sound = NSSound(contentsOfFile: soundPath, byReference: true) else {
            VocaLogger.warning(.soundManager, "Could not load system sound: \(name)")
            return
        }

        sound.volume = volume
        sound.delegate = self

        return await withCheckedContinuation { continuation in
            continuationLock.lock()
            soundCompletionContinuation = continuation
            continuationLock.unlock()

            sound.play()

            // Timeout after 1 second to prevent stuck sounds from blocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.continuationLock.lock()
                if self.soundCompletionContinuation != nil {
                    VocaLogger.warning(.soundManager, "Sound playback timeout for: \(name)")
                    self.soundCompletionContinuation?.resume()
                    self.soundCompletionContinuation = nil
                }
                self.continuationLock.unlock()
            }
        }
    }

    // MARK: - NSSoundDelegate

    /// Called when sound finishes playing
    nonisolated func sound(_ sound: NSSound, didFinishPlaying FinishedPlaying: Bool) {
        // Dispatch back to main thread to safely access and resume continuation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.continuationLock.lock()
            if let continuation = self.soundCompletionContinuation {
                continuation.resume()
                self.soundCompletionContinuation = nil
            }
            self.continuationLock.unlock()
        }
    }
}
