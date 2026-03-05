// SoundManager.swift
// VocaMac
//
// Plays audio feedback sounds for recording start/stop events.
// Uses macOS system sounds for soft, pleasing audio cues.

import Foundation
import AppKit

final class SoundManager {

    // MARK: - Sound Names

    /// Soft pop sound for recording start
    private let startSoundName = "Pop"

    /// Hollow bottle sound for recording stop
    private let stopSoundName = "Bottle"

    // MARK: - Properties

    /// Volume for sound effects (0.0 to 1.0)
    var volume: Float = 0.5

    // MARK: - Public API

    /// Play the recording-started sound
    func playStartSound() {
        playSystemSound(startSoundName)
    }

    /// Play the recording-stopped sound
    func playStopSound() {
        playSystemSound(stopSoundName)
    }

    // MARK: - Private

    /// Play a macOS system sound by name
    private func playSystemSound(_ name: String) {
        let soundPath = "/System/Library/Sounds/\(name).aiff"
        guard let sound = NSSound(contentsOfFile: soundPath, byReference: true) else {
            NSLog("[SoundManager] Could not load system sound: %@", name)
            return
        }
        sound.volume = volume
        sound.play()
    }
}
