// AudioEngine.swift
// VocaMac
//
// Real-time microphone audio capture using AVAudioEngine.
// Captures audio in the format required by whisper.cpp (16kHz, mono, Float32 PCM).

import Foundation
import AVFoundation

final class AudioEngine {

    // MARK: - Properties

    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var isCurrentlyRecording = false
    private let bufferQueue = DispatchQueue(label: "com.vocamac.audio-buffer", qos: .userInteractive)

    // Silence detection
    private var lastSoundTime: Date = Date()
    private var silenceThreshold: Float = 0.01
    private var silenceDuration: Double = 2.0
    private var maxDuration: TimeInterval = 60.0
    private var recordingStartTime: Date = Date()

    // Audio level throttling
    private var lastLevelReportTime: Date = Date()
    private let levelReportInterval: TimeInterval = 1.0 / 15.0  // ~15 Hz

    /// Target audio format for whisper.cpp
    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Callbacks

    /// Called with the current audio level (0.0 - 1.0) for UI visualization
    var onAudioLevel: ((Float) -> Void)?

    /// Called when silence is detected for the configured duration
    var onSilenceDetected: (() -> Void)?

    /// Called when max recording duration is reached
    var onMaxDurationReached: (() -> Void)?

    // MARK: - Permission Handling

    /// Check current microphone permission status
    func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            completion(false)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Request microphone permission from the user
    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // MARK: - Recording Control

    /// Start recording audio from the microphone
    /// - Parameters:
    ///   - silenceThreshold: RMS energy threshold below which audio is considered silence
    ///   - silenceDuration: Seconds of silence before triggering silence detection callback
    ///   - maxDuration: Maximum recording duration in seconds
    func startRecording(
        silenceThreshold: Float = 0.01,
        silenceDuration: Double = 2.0,
        maxDuration: TimeInterval = 60.0
    ) {
        guard !isCurrentlyRecording else { return }

        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.maxDuration = maxDuration

        // Reset state
        bufferQueue.sync {
            audioBuffer.removeAll(keepingCapacity: true)
        }
        lastSoundTime = Date()
        recordingStartTime = Date()
        isCurrentlyRecording = true

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap on the input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat)
        }

        do {
            try engine.start()
        } catch {
            print("[AudioEngine] Failed to start audio engine: \(error)")
            isCurrentlyRecording = false
        }
    }

    /// Stop recording and return the captured audio samples
    /// - Returns: Array of Float32 PCM samples at 16kHz mono
    func stopRecording() -> [Float] {
        guard isCurrentlyRecording else { return [] }

        isCurrentlyRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let samples: [Float] = bufferQueue.sync {
            let copy = audioBuffer
            audioBuffer.removeAll(keepingCapacity: true)
            return copy
        }

        return samples
    }

    // MARK: - Audio Processing

    /// Process an incoming audio buffer from AVAudioEngine
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard isCurrentlyRecording else { return }

        // Check max duration
        let elapsed = Date().timeIntervalSince(recordingStartTime)
        if elapsed >= maxDuration {
            DispatchQueue.main.async { [weak self] in
                self?.onMaxDurationReached?()
            }
            return
        }

        // Convert to whisper format (16kHz, mono, Float32)
        guard let convertedBuffer = convertToWhisperFormat(buffer, from: inputFormat) else {
            return
        }

        // Calculate audio energy for level reporting and silence detection
        let energy = calculateRMSEnergy(convertedBuffer)

        // Report audio level (throttled)
        let now = Date()
        if now.timeIntervalSince(lastLevelReportTime) >= levelReportInterval {
            lastLevelReportTime = now
            let normalizedLevel = min(energy / 0.3, 1.0)  // Normalize to 0-1 range
            onAudioLevel?(normalizedLevel)
        }

        // Silence detection
        if energy > silenceThreshold {
            lastSoundTime = now
        } else if now.timeIntervalSince(lastSoundTime) >= silenceDuration {
            DispatchQueue.main.async { [weak self] in
                self?.onSilenceDetected?()
            }
            return
        }

        // Append samples to buffer
        if let channelData = convertedBuffer.floatChannelData {
            let frameCount = Int(convertedBuffer.frameLength)
            bufferQueue.sync {
                audioBuffer.reserveCapacity(audioBuffer.count + frameCount)
                for i in 0..<frameCount {
                    audioBuffer.append(channelData[0][i])
                }
            }
        }
    }

    /// Convert an audio buffer to whisper.cpp's required format (16kHz, mono, Float32)
    private func convertToWhisperFormat(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let whisperFormat = AudioEngine.whisperFormat

        // If input is already in the right format, return as-is
        if inputFormat.sampleRate == whisperFormat.sampleRate
            && inputFormat.channelCount == whisperFormat.channelCount
            && inputFormat.commonFormat == whisperFormat.commonFormat {
            return buffer
        }

        // Create a converter
        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            print("[AudioEngine] Failed to create audio format converter")
            return nil
        }

        // Calculate output frame capacity based on sample rate ratio
        let ratio = whisperFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: whisperFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[AudioEngine] Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    /// Calculate the RMS (root mean square) energy of an audio buffer
    private func calculateRMSEnergy(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }

        var sumSquares: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[0][i]
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameCount))
    }

    // MARK: - Audio Device Enumeration

    /// List available audio input devices
    static func availableInputDevices() -> [AudioDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices

        let defaultDevice = AVCaptureDevice.default(for: .audio)

        return devices.map { device in
            AudioDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultDevice?.uniqueID
            )
        }
    }
}

// MARK: - AudioDevice

/// Represents an available audio input device
struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
}
