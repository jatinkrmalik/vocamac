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
    case missingModelDirectory(String)
    case tokenizerAssetsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let name):
            return "Model '\(name)' is not available."
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .deviceNotSupported(let model):
            return "Model '\(model)' is too large for this device."
        case .missingModelDirectory(let path):
            return "Model files are missing at: \(path)"
        case .tokenizerAssetsUnavailable(let model):
            return "Tokenizer assets are missing for model '\(model)'."
        }
    }
}

// MARK: - ModelManager

final class ModelManager {

    // MARK: - Properties

    /// HuggingFace repository for WhisperKit CoreML models
    private let modelRepo = "argmaxinc/whisperkit-coreml"
    private let bundledModelsDirectory = "BundledModels/whisperkit-coreml"
    private let requiredTokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]
    private let requiredModelDirectories = [
        "MelSpectrogram.mlmodelc",
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc"
    ]

    private var fileManager: FileManager { .default }

    private var bundledModelsBase: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(bundledModelsDirectory, isDirectory: true)
    }

    private func installedModelDirectory(for size: ModelSize) -> URL {
        modelStorageBase.appendingPathComponent(whisperKitModelName(for: size), isDirectory: true)
    }

    private func hasRequiredModelAssets(at directory: URL) -> Bool {
        requiredModelDirectories.allSatisfy { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private func hasRequiredTokenizerAssets(at directory: URL) -> Bool {
        requiredTokenizerFiles.allSatisfy { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private func createParentDirectoryIfNeeded(for directory: URL) throws {
        try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func replaceDirectory(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func tokenizerAssetSourceDirectory(for modelDirectory: URL) -> URL? {
        let snapshotsDirectory = modelDirectory.appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshotDirectories = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return snapshotDirectories.first(where: { snapshotURL in
            (try? snapshotURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        })
    }

    private func repairTokenizerAssetsIfNeeded(in modelDirectory: URL, modelName: String) throws {
        guard !hasRequiredTokenizerAssets(at: modelDirectory) else { return }
        guard let sourceDirectory = tokenizerAssetSourceDirectory(for: modelDirectory),
              hasRequiredTokenizerAssets(at: sourceDirectory) else {
            throw ModelManagerError.tokenizerAssetsUnavailable(modelName)
        }

        for fileName in requiredTokenizerFiles {
            let sourceURL = sourceDirectory.appendingPathComponent(fileName)
            let destinationURL = modelDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        VocaLogger.info(.modelManager, "Repaired tokenizer assets for \(modelName)")
    }

    private func validateModelDirectory(_ directory: URL, modelName: String) throws {
        guard hasRequiredModelAssets(at: directory) else {
            throw ModelManagerError.missingModelDirectory(directory.path)
        }
        try repairTokenizerAssetsIfNeeded(in: directory, modelName: modelName)
    }

    private func installBundledModel(from sourceDirectory: URL, to destinationDirectory: URL, modelName: String) throws {
        try createParentDirectoryIfNeeded(for: destinationDirectory)
        try replaceDirectory(at: destinationDirectory, with: sourceDirectory)
        try validateModelDirectory(destinationDirectory, modelName: modelName)
        VocaLogger.info(.modelManager, "Installed bundled model: \(modelName)")
    }

    private func bundledModelDirectory(forModelNamed modelName: String) -> URL? {
        guard let bundledModelsBase else { return nil }
        let directory = bundledModelsBase.appendingPathComponent(modelName, isDirectory: true)
        return fileManager.fileExists(atPath: directory.path) ? directory : nil
    }

    private func isBundledModelSupported(_ size: ModelSize) -> Bool {
        size == .tiny
    }

    private func ensureInstalledModelReady(for size: ModelSize) throws -> URL {
        let modelName = whisperKitModelName(for: size)
        let installedDirectory = installedModelDirectory(for: size)
        guard fileManager.fileExists(atPath: installedDirectory.path) else {
            throw ModelManagerError.missingModelDirectory(installedDirectory.path)
        }
        try validateModelDirectory(installedDirectory, modelName: modelName)
        return installedDirectory
    }

    func bundledModelFolder(for size: ModelSize) -> URL? {
        guard isBundledModelSupported(size) else { return nil }
        return bundledModelDirectory(forModelNamed: whisperKitModelName(for: size))
    }

    @discardableResult
    func installBundledModelIfAvailable(for size: ModelSize) throws -> Bool {
        guard let sourceDirectory = bundledModelFolder(for: size) else { return false }
        let modelName = whisperKitModelName(for: size)
        let destinationDirectory = installedModelDirectory(for: size)
        try installBundledModel(from: sourceDirectory, to: destinationDirectory, modelName: modelName)
        return true
    }

    func ensureTokenizerAssets(for size: ModelSize) throws -> URL {
        try ensureInstalledModelReady(for: size)
    }


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
        guard let modelDir = modelFolder(for: size) else { return false }
        return hasRequiredModelAssets(at: modelDir)
    }

    /// Get the local folder path for a downloaded or installed model
    func modelFolder(for size: ModelSize) -> URL? {
        let modelDir = installedModelDirectory(for: size)
        if fileManager.fileExists(atPath: modelDir.path) {
            return modelDir
        }
        return nil
    }

    /// List all downloaded models
    func downloadedModels() -> [ModelSize] {
        ModelSize.allCases.filter { isModelDownloaded($0) }
    }

    /// Check if a model size is supported on this device.
    ///
    /// Uses exact prefix boundary matching: "openai_whisper-large-v3" matches
    /// versioned variants like "openai_whisper-large-v3-v20240930_626MB" but NOT
    /// different models like "openai_whisper-large-v3_turbo-v20240930_626MB".
    /// Also checks the disabled list — if any exact variant is disabled, the model
    /// is considered unsupported to avoid recommending models the device can't run.
    func isModelSupported(_ size: ModelSize) -> Bool {
        let rec = WhisperKit.recommendedModels()
        let modelPrefix = whisperKitModelName(for: size)

        // Match exact model name or versioned variants (prefix + "-")
        // but not different models that share a prefix (e.g. large-v3_turbo)
        let matchesModel: (String) -> Bool = { name in
            name == modelPrefix || name.hasPrefix(modelPrefix + "-")
        }

        // If any exact variant of this model is in the disabled list, it's unsupported
        if rec.disabled.contains(where: matchesModel) {
            return false
        }

        return rec.supported.contains(where: matchesModel)
    }

    /// Map a WhisperKit model name back to a ModelSize, if it matches one of our known sizes.
    ///
    /// Uses exact prefix boundary matching, same as `isModelSupported`.
    func modelSize(from whisperKitName: String) -> ModelSize? {
        for size in ModelSize.allCases {
            let prefix = whisperKitModelName(for: size)
            if whisperKitName == prefix || whisperKitName.hasPrefix(prefix + "-") {
                return size
            }
        }
        return nil
    }

    // MARK: - Model Download

    /// After WhisperKit downloads a model, consolidate the files from its
    /// temp/symlinked cache into our permanent installedModelDirectory.
    /// WhisperKit stores CoreML models in temp directories with symlinks —
    /// macOS may clean those up, causing "downloaded" models to vanish.
    private func consolidateWhisperKitDownload(for size: ModelSize) throws {
        let modelName = whisperKitModelName(for: size)
        let destination = installedModelDirectory(for: size)

        // Already consolidated — nothing to do
        if hasRequiredModelAssets(at: destination) && hasRequiredTokenizerAssets(at: destination) {
            return
        }

        // Find the WhisperKit download location (may be a symlink to temp)
        let wkDownloadDir = modelStorageBase.appendingPathComponent(modelName, isDirectory: true)

        guard fileManager.fileExists(atPath: wkDownloadDir.path),
              hasRequiredModelAssets(at: wkDownloadDir) else {
            VocaLogger.warning(.modelManager, "WhisperKit download not found at \(wkDownloadDir.path) — skipping consolidation")
            return
        }

        // Copy from WhisperKit's cache to our permanent location
        try createParentDirectoryIfNeeded(for: destination)
        try replaceDirectory(at: destination, with: wkDownloadDir)

        // Ensure tokenizer files are present (may need to copy from openai/ cache)
        if !hasRequiredTokenizerAssets(at: destination) {
            let tokenizerDir = downloadBase
                .appendingPathComponent("models")
                .appendingPathComponent("openai")
                .appendingPathComponent("whisper-\(size.rawValue)", isDirectory: true)
            if hasRequiredTokenizerAssets(at: tokenizerDir) {
                for file in requiredTokenizerFiles {
                    let src = tokenizerDir.appendingPathComponent(file)
                    let dst = destination.appendingPathComponent(file)
                    if fileManager.fileExists(atPath: src.path) {
                        try? fileManager.removeItem(at: dst)
                        try fileManager.copyItem(at: src, to: dst)
                    }
                }
                VocaLogger.info(.modelManager, "Consolidated tokenizer assets from openai cache for \(modelName)")
            }
        }

        VocaLogger.info(.modelManager, "Consolidated WhisperKit download for \(modelName) to permanent location")
    }

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
            try? await Task.sleep(nanoseconds: 50_000_000)

            // WhisperKit downloads CoreML models to a temp directory with a
            // symlink from modelStorageBase. macOS may clean up temp files,
            // so we consolidate into a permanent location — the same path
            // used by installBundledModel. This ensures downloaded models
            // survive temp directory cleanup.
            try consolidateWhisperKitDownload(for: size)

            onProgress(1.0)
            let installedDir = installedModelDirectory(for: size)
            VocaLogger.info(.modelManager, "Model '\(whisperKitModelName(for: size))' downloaded successfully to: \(installedDir.path)")
        } catch {
            VocaLogger.error(.modelManager, "Download failed for '\(whisperKitModelName(for: size))': \(error.localizedDescription)")
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
        let modelDir = installedModelDirectory(for: size)

        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
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
