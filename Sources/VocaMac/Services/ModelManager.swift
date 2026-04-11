// ModelManager.swift
// VocaMac
//
// Manages whisper model lifecycle using WhisperKit's built-in model management.
// Models are CoreML format, downloaded from HuggingFace and cached locally.

import Foundation
import WhisperKit

// MARK: - ModelManagerError

enum ModelManagerError: LocalizedError {
    case modelNotAvailable(String)
    case downloadFailed(reason: String)
    case deviceNotSupported(model: String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let name):
            return "Model '\(name)' is not available."
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .deviceNotSupported(let model):
            return "Model '\(model)' is too large for this device."
        }
    }
}

// MARK: - ModelManager

final class ModelManager {

    // MARK: - Properties

    /// HuggingFace repository for WhisperKit CoreML models
    private let modelRepo = "argmaxinc/whisperkit-coreml"

    /// Local base directory passed to WhisperKit's downloadBase config.
    /// WhisperKit creates its own subdirectory structure under this path.
    private var downloadBase: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("VocaMac")
            .appendingPathComponent("models")
    }

    /// Actual directory where WhisperKit stores downloaded model files.
    /// WhisperKit nests models under: downloadBase/models/<repo>/
    private var modelStorageBase: URL {
        downloadBase
            .appendingPathComponent("models")
            .appendingPathComponent(modelRepo)
    }

    // MARK: - Model Discovery

    /// Get WhisperKit's recommendation for the current device
    func deviceRecommendation() -> (defaultModel: String, supported: [String], disabled: [String]) {
        let rec = WhisperKit.recommendedModels()
        return (
            defaultModel: rec.default,
            supported: rec.supported,
            disabled: rec.disabled
        )
    }

    /// Map a ModelSize enum to WhisperKit model variant name
    func whisperKitModelName(for size: ModelSize) -> String {
        switch size {
        case .tiny:    return "openai_whisper-tiny"
        case .base:    return "openai_whisper-base"
        case .small:   return "openai_whisper-small"
        case .medium:  return "openai_whisper-medium"
        case .largeV3: return "openai_whisper-large-v3"
        }
    }

    /// Check if a model is downloaded locally
    func isModelDownloaded(_ size: ModelSize) -> Bool {
        let modelName = whisperKitModelName(for: size)
        let modelDir = modelStorageBase.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    /// Get the local folder path for a downloaded model
    func modelFolder(for size: ModelSize) -> URL? {
        let modelName = whisperKitModelName(for: size)
        let modelDir = modelStorageBase.appendingPathComponent(modelName)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            return modelDir
        }
        return nil
    }

    /// List all downloaded models
    func downloadedModels() -> [ModelSize] {
        ModelSize.allCases.filter { isModelDownloaded($0) }
    }

    /// Check if a model size is supported on this device
    func isModelSupported(_ size: ModelSize) -> Bool {
        let rec = WhisperKit.recommendedModels()
        // A model is supported if any variant of its size appears in the supported list.
        // We check the supported list (not disabled) to avoid false positives from
        // substring matching — e.g. "large-v3" matching "large-v3_turbo" in disabled.
        let modelPrefix = whisperKitModelName(for: size)
        return rec.supported.contains(where: { $0.hasPrefix(modelPrefix) })
    }

    // MARK: - Model Download

    /// Download a model using WhisperKit's built-in download mechanism
    /// The model will be downloaded from HuggingFace and cached locally.
    /// - Parameters:
    ///   - size: The model size to download
    ///   - onProgress: Progress callback (0.0 to 1.0)
    func downloadModel(
        size: ModelSize,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        VocaLogger.info(.modelManager, "Downloading model: \(whisperKitModelName(for: size))")

        // Ensure download directory exists
        try FileManager.default.createDirectory(
            at: downloadBase,
            withIntermediateDirectories: true
        )

        do {
            // WhisperKit handles downloading from HuggingFace automatically
            // when we initialize with a model name. We create a temporary
            // instance just to trigger the download.
            let config = WhisperKitConfig(model: whisperKitModelName(for: size))
            config.downloadBase = downloadBase
            config.prewarm = false
            config.load = false  // Don't load into memory, just download

            // Report initial progress
            onProgress(0.05)

            // Simulate progress while downloading, since WhisperKit doesn't
            // expose granular download progress in this usage pattern.
            // Use `try` (not `try?`) so Task.sleep throws on cancellation,
            // which cleanly exits the loop.
            let progressTask = Task { @Sendable in
                var currentProgress = 0.05
                do {
                    while !Task.isCancelled && currentProgress < 0.90 {
                        try await Task.sleep(nanoseconds: 800_000_000)  // 0.8s intervals
                        guard !Task.isCancelled else { break }
                        currentProgress += Double.random(in: 0.03...0.08)
                        currentProgress = min(currentProgress, 0.90)
                        onProgress(currentProgress)
                    }
                } catch {
                    // Task was cancelled — stop updating progress
                }
            }

            let _ = try await WhisperKit(config)

            // Stop the simulated progress and report completion
            progressTask.cancel()
            // Small delay to ensure the cancelled task has stopped
            // before we send the final progress update
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            onProgress(1.0)
            VocaLogger.info(.modelManager, "Model '\(whisperKitModelName(for: size))' downloaded successfully")
        } catch {
            throw ModelManagerError.downloadFailed(reason: error.localizedDescription)
        }
    }

    /// Cancel an active download (WhisperKit handles this internally)
    func cancelDownload(for size: ModelSize) {
        // WhisperKit manages downloads internally via URLSession
        // For MVP, we rely on task cancellation at the caller level
        VocaLogger.info(.modelManager, "Download cancellation requested for \(size.displayName)")
    }

    // MARK: - Model Deletion

    /// Delete a downloaded model's local files
    func deleteModel(_ size: ModelSize) throws {
        let modelName = whisperKitModelName(for: size)
        let modelDir = modelStorageBase.appendingPathComponent(modelName)

        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
            VocaLogger.info(.modelManager, "Deleted model: \(modelName)")
        }
    }

    // MARK: - Utilities

    /// Get total disk space used by downloaded models
    func totalDiskUsage() -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelStorageBase.path) else { return 0 }

        var totalSize: Int64 = 0
        if let enumerator = fm.enumerator(at: modelStorageBase, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attrs.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }

    /// Human-readable disk usage string
    func diskUsageDescription() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalDiskUsage())
    }
}

// MARK: - ModelManaging Conformance

extension ModelManager: ModelManaging {}
