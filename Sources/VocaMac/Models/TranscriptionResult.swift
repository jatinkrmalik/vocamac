// TranscriptionResult.swift
// VocaMac
//
// Represents the output of a VocaMac transcription.
// Named VocaTranscription to avoid collision with WhisperKit's TranscriptionResult.

import Foundation

struct VocaTranscription: Identifiable {
    /// Unique identifier for this transcription
    let id: UUID

    /// The transcribed text
    let text: String

    /// Time taken to perform the transcription (seconds)
    let duration: TimeInterval

    /// Detected or specified language (ISO 639-1 code)
    let detectedLanguage: String

    /// When the transcription was performed
    let timestamp: Date

    /// Length of the source audio in seconds
    let audioLengthSeconds: Double

    /// Which model was used for this transcription
    let modelUsed: ModelSize

    init(
        text: String,
        duration: TimeInterval,
        detectedLanguage: String,
        audioLengthSeconds: Double,
        modelUsed: ModelSize
    ) {
        self.id = UUID()
        self.text = text
        self.duration = duration
        self.detectedLanguage = detectedLanguage
        self.timestamp = Date()
        self.audioLengthSeconds = audioLengthSeconds
        self.modelUsed = modelUsed
    }
}
