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

    /// Local base directory for downloaded models
    private var downloadBase: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("VocaMac")
            .appendingPathComponent("models")
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
        let modelDir = downloadBase.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    /// Get the local folder path for a downloaded model
    func modelFolder(for size: ModelSize) -> URL? {
        let modelName = whisperKitModelName(for: size)
        let modelDir = downloadBase.appendingPathComponent(modelName)
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
        // A model is supported if it's not in the disabled list
        return !rec.disabled.contains(where: { $0.contains(size.rawValue) })
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
        print("[ModelManager] Downloading model: \(whisperKitModelName(for: size))")

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
            onProgress(0.1)

            // Simulate progress while downloading, since WhisperKit doesn't expose granular progress
            let progressTask = Task {
                var currentProgress = 0.1
                while currentProgress < 0.95 {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second intervals
                    currentProgress += Double.random(in: 0.05...0.15)
                    onProgress(min(currentProgress, 0.95))
                }
            }

            let _ = try await WhisperKit(config)
            
            // Cancel progress simulation and report completion
            progressTask.cancel()
            onProgress(1.0)
            print("[ModelManager] Model '\(whisperKitModelName(for: size))' downloaded successfully")
        } catch {
            throw ModelManagerError.downloadFailed(reason: error.localizedDescription)
        }
    }

    /// Cancel an active download (WhisperKit handles this internally)
    func cancelDownload(for size: ModelSize) {
        // WhisperKit manages downloads internally via URLSession
        // For MVP, we rely on task cancellation at the caller level
        print("[ModelManager] Download cancellation requested for \(size.displayName)")
    }

    // MARK: - Model Deletion

    /// Delete a downloaded model's local files
    func deleteModel(_ size: ModelSize) throws {
        let modelName = whisperKitModelName(for: size)
        let modelDir = downloadBase.appendingPathComponent(modelName)

        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
            print("[ModelManager] Deleted model: \(modelName)")
        }
    }

    // MARK: - Utilities

    /// Get total disk space used by downloaded models
    func totalDiskUsage() -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: downloadBase.path) else { return 0 }

        var totalSize: Int64 = 0
        if let enumerator = fm.enumerator(at: downloadBase, includingPropertiesForKeys: [.fileSizeKey]) {
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
