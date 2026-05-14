// AudioEngine.swift
// VocaMac
//
// Real-time microphone audio capture using AVAudioEngine.
// Captures audio in the format required by whisper.cpp (16kHz, mono, Float32 PCM).

import Foundation
import AVFoundation
import VocaMacObjC

final class AudioEngine {

    // MARK: - Properties

    /// AVAudioEngine is created lazily when recording starts and torn down when
    /// recording stops. Keeping it alive while idle holds an input route on the
    /// system mic, which on Bluetooth devices like AirPods forces the headset
    /// (HFP/SCO) profile and breaks remote media controls (e.g. tap-to-pause)
    /// for any other app playing audio.
    private var engine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var _isCurrentlyRecording = false
    private let bufferQueue = DispatchQueue(label: "com.vocamac.audio-buffer", qos: .userInteractive)
    private let lifecycleQueue = DispatchQueue(label: "com.vocamac.audio-engine.lifecycle", qos: .userInitiated)

    var isCurrentlyRecording: Bool {
        lifecycleQueue.sync { _isCurrentlyRecording }
    }

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

    /// Called when the audio device configuration changes (e.g., mic unplugged/replugged).
    /// The engine is automatically stopped and reset when this happens.
    /// AppState should use this to recover from a stuck recording state.
    var onAudioDeviceChanged: (() -> Void)?

    // MARK: - Initialization

    init() {
        // Note: we intentionally do NOT create the AVAudioEngine here, nor
        // register for AVAudioEngineConfigurationChange. Both actions cause the
        // engine's input node to materialise and claim the system input route,
        // which on Bluetooth headsets forces the HFP profile. The observer is
        // attached as part of `acquireEngine()` instead, and torn down by
        // `releaseEngine()` when recording stops.
    }

    deinit {
        // Make sure any active engine and its observer are released. This is a
        // safety net — under normal flows `stopRecording`/`forceReset` will
        // already have torn things down.
        if let engine {
            NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        }
    }

    // MARK: - Engine Lifecycle

    /// Lazily create the AVAudioEngine and start observing configuration changes.
    /// Must be called on `lifecycleQueue`.
    private func acquireEngine() -> AVAudioEngine {
        if let engine { return engine }
        let newEngine = AVAudioEngine()
        engine = newEngine
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: newEngine
        )
        VocaLogger.debug(.audioEngine, "AVAudioEngine instance acquired")
        return newEngine
    }

    /// Tear down the AVAudioEngine, removing its observer and releasing the
    /// underlying input route so other apps (and Bluetooth audio profiles)
    /// aren't affected while we're idle.
    /// Must be called on `lifecycleQueue`.
    private func releaseEngine() {
        guard let engine else { return }
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        self.engine = nil
        VocaLogger.debug(.audioEngine, "AVAudioEngine instance released")
    }

    // MARK: - Audio Configuration Change

    /// Called when macOS detects an audio hardware configuration change.
    /// This happens when a microphone is unplugged/replugged, Bluetooth audio
    /// disconnects, or the default audio device changes (e.g., after sleep).
    ///
    /// When this fires during an active recording, the engine's internal state
    /// is invalidated — the installed tap references a stale format and no audio
    /// flows. We must stop, reset, and notify AppState so it can recover.
    @objc private func handleAudioConfigurationChange(_ notification: Notification) {
        lifecycleQueue.async { [weak self] in
            guard let self = self else { return }
            VocaLogger.info(.audioEngine, "Audio configuration changed (device plug/unplug or route change)")

            let wasRecording = self._isCurrentlyRecording

            if wasRecording {
                VocaLogger.warning(.audioEngine, "Configuration changed while recording — forcing stop and reset")
                // Tear down the stale recording state
                self._isCurrentlyRecording = false
                self.silenceCallbackFired = false
                self.maxDurationCallbackFired = false
                self.removeInputTap(reason: "audio configuration change")
                self.engine?.stop()
            }

            // Drop the engine entirely so the next recording starts from a
            // clean instance bound to the new default device.
            self.releaseEngine()
            VocaLogger.info(.audioEngine, "Audio engine released after configuration change")

            if wasRecording {
                // Notify AppState on the main queue so it can handle the interrupted recording
                DispatchQueue.main.async { [weak self] in
                    self?.onAudioDeviceChanged?()
                }
            }
        }
    }

    // MARK: - Permission Handling

    /// Check current microphone permission status (tri-state)
    func checkPermissionStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
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
        lifecycleQueue.sync {
            guard !self._isCurrentlyRecording else { return }

            self.silenceThreshold = silenceThreshold
            self.silenceDuration = silenceDuration
            self.maxDuration = maxDuration

            resetRecordingState()
            _isCurrentlyRecording = true

            let engine = acquireEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard isValidInputFormat(inputFormat) else {
                VocaLogger.error(
                    .audioEngine,
                    "Invalid input format before recording start: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount)"
                )
                recoverFromStartFailure(notifyAppState: true)
                return
            }

            // A previous failed start can leave a tap installed even when our
            // recording flag is false. Remove any stale tap before installing a
            // fresh one; otherwise AVAudioEngine raises an uncaught NSException.
            removeInputTap(reason: "pre-start cleanup")

            var startError: Error?
            let exception = VocaObjCExceptionCatcher.catchException { [weak self] in
                guard let self = self else { return }

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    self?.processAudioBuffer(buffer, inputFormat: inputFormat)
                }

                do {
                    try engine.start()
                } catch {
                    startError = error
                }
            }

            if let exception {
                VocaLogger.error(.audioEngine, "AVAudioEngine exception while starting recording: \(exception.localizedDescription)")
                recoverFromStartFailure(notifyAppState: true)
                return
            }

            if let startError {
                VocaLogger.error(.audioEngine, "Failed to start audio engine: \(startError.localizedDescription)")
                recoverFromStartFailure(notifyAppState: true)
                return
            }
        }
    }

    /// Stop recording and return the captured audio samples
    /// - Returns: Array of Float32 PCM samples at 16kHz mono
    func stopRecording() -> [Float] {
        lifecycleQueue.sync {
            guard _isCurrentlyRecording else { return [] }

            _isCurrentlyRecording = false
            removeInputTap(reason: "stop recording")
            engine?.stop()

            let samples = capturedSamplesAndResetBuffer()

            // Release the engine so we don't keep holding the system input
            // route (and forcing AirPods into HFP) while idle.
            releaseEngine()

            return samples
        }
    }

    /// Forcibly reset the audio engine to a clean state, regardless of current state.
    /// This is a last-resort recovery mechanism — it unconditionally tears down
    /// taps, stops the engine, clears buffers, and resets all flags.
    /// Use when the engine is suspected to be in an inconsistent state.
    func forceReset() {
        lifecycleQueue.sync {
            VocaLogger.warning(.audioEngine, "Force reset requested (wasRecording=\(_isCurrentlyRecording))")

            _isCurrentlyRecording = false
            silenceCallbackFired = false
            maxDurationCallbackFired = false

            removeInputTap(reason: "force reset")
            engine?.stop()
            engine?.reset()
            clearAudioBuffer()

            // Drop the engine entirely so the input route is released. The
            // next recording will create a fresh instance.
            releaseEngine()

            VocaLogger.info(.audioEngine, "Force reset complete — engine is clean")
        }
    }

    // MARK: - Lifecycle Helpers

    /// Resets per-recording state before a new capture attempt.
    private func resetRecordingState() {
        clearAudioBuffer()
        lastSoundTime = Date()
        recordingStartTime = Date()
        silenceCallbackFired = false
        maxDurationCallbackFired = false
    }

    /// Clears captured audio samples while preserving buffer capacity.
    private func clearAudioBuffer() {
        bufferQueue.sync {
            audioBuffer.removeAll(keepingCapacity: true)
        }
    }

    /// Returns captured samples and clears the backing buffer.
    private func capturedSamplesAndResetBuffer() -> [Float] {
        bufferQueue.sync {
            let copy = audioBuffer
            audioBuffer.removeAll(keepingCapacity: true)
            return copy
        }
    }

    /// Checks whether a hardware input format is safe to pass to AVAudioEngine.
    /// Invalid or transient formats can cause installTap to raise NSException.
    private func isValidInputFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate.isFinite && format.sampleRate > 0 && format.channelCount > 0
    }

    /// Removes the current input tap while converting AVFoundation NSExceptions
    /// into log messages instead of process aborts. No-op if the engine has
    /// already been released.
    private func removeInputTap(reason: String) {
        guard let engine else { return }
        let exception = VocaObjCExceptionCatcher.catchException {
            engine.inputNode.removeTap(onBus: 0)
        }

        if let exception {
            VocaLogger.warning(.audioEngine, "Ignoring AVAudioEngine exception while removing tap during \(reason): \(exception.localizedDescription)")
        }
    }

    /// Restores AudioEngine to a clean idle state after any failed start attempt.
    private func recoverFromStartFailure(notifyAppState: Bool) {
        _isCurrentlyRecording = false
        silenceCallbackFired = false
        maxDurationCallbackFired = false
        removeInputTap(reason: "start failure")
        engine?.stop()
        engine?.reset()
        clearAudioBuffer()

        // Release the engine so a failed start doesn't leave us holding the
        // system input route (and forcing AirPods into HFP) until the next
        // attempt.
        releaseEngine()

        if notifyAppState {
            DispatchQueue.main.async { [weak self] in
                self?.onAudioDeviceChanged?()
            }
        }
    }

    // MARK: - Audio Processing

    /// Whether silence detection has already fired (prevents repeated callbacks)
    private var silenceCallbackFired = false

    /// Whether max duration callback has already fired
    private var maxDurationCallbackFired = false

    /// Process an incoming audio buffer from AVAudioEngine
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard isCurrentlyRecording else { return }

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

        // Always append audio samples to the buffer BEFORE checking stop conditions.
        // This ensures no audio frames are discarded when silence or max duration
        // is detected — the triggering frame and any trailing audio are preserved.
        if let channelData = convertedBuffer.floatChannelData {
            let frameCount = Int(convertedBuffer.frameLength)
            bufferQueue.sync {
                audioBuffer.reserveCapacity(audioBuffer.count + frameCount)
                for i in 0..<frameCount {
                    audioBuffer.append(channelData[0][i])
                }
            }
        }

        // Check max duration (fire callback only once)
        let elapsed = now.timeIntervalSince(recordingStartTime)
        if elapsed >= maxDuration && !maxDurationCallbackFired {
            maxDurationCallbackFired = true
            DispatchQueue.main.async { [weak self] in
                self?.onMaxDurationReached?()
            }
            return
        }

        // Silence detection
        if energy > silenceThreshold {
            lastSoundTime = now
            silenceCallbackFired = false  // Reset so silence can be detected again after speech resumes
        } else if now.timeIntervalSince(lastSoundTime) >= silenceDuration && !silenceCallbackFired {
            silenceCallbackFired = true
            DispatchQueue.main.async { [weak self] in
                self?.onSilenceDetected?()
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
            VocaLogger.error(.audioEngine, "Failed to create audio format converter")
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
            VocaLogger.error(.audioEngine, "Conversion error: \(error)")
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

// MARK: - AudioRecording Conformance

extension AudioEngine: AudioRecording {}
