// WhisperModel.swift
// VocaMac
//
// Model metadata types for whisper model variants and their runtime state.

import Foundation

// MARK: - ModelSize

/// Whisper model size variants with their properties
enum ModelSize: String, CaseIterable, Codable, Identifiable {
    case tiny     = "tiny"
    case base     = "base"
    case small    = "small"
    case medium   = "medium"
    case largeV3  = "large-v3"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .tiny:    return "Tiny (Fastest)"
        case .base:    return "Base"
        case .small:   return "Small"
        case .medium:  return "Medium"
        case .largeV3: return "Large v3 (Best Quality)"
        }
    }

    /// Model file name in GGML format
    var fileName: String {
        "ggml-\(rawValue).bin"
    }

    /// Approximate file size on disk in bytes
    var fileSizeBytes: Int64 {
        switch self {
        case .tiny:    return 39_000_000
        case .base:    return 142_000_000
        case .small:   return 466_000_000
        case .medium:  return 1_500_000_000
        case .largeV3: return 3_100_000_000
        }
    }

    /// Human-readable file size string
    var fileSizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }

    /// Approximate RAM required for inference in GB
    var ramRequiredGB: Double {
        switch self {
        case .tiny:    return 1.0
        case .base:    return 1.5
        case .small:   return 2.0
        case .medium:  return 5.0
        case .largeV3: return 10.0
        }
    }

    /// Relative speed indicator (1 = fastest)
    var relativeSpeed: Int {
        switch self {
        case .tiny:    return 1
        case .base:    return 2
        case .small:   return 4
        case .medium:  return 8
        case .largeV3: return 16
        }
    }

    /// Accuracy quality descriptor
    var qualityDescription: String {
        switch self {
        case .tiny:    return "Good"
        case .base:    return "Better"
        case .small:   return "Great"
        case .medium:  return "Excellent"
        case .largeV3: return "Best"
        }
    }

    /// Download URL from Hugging Face
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

// MARK: - WhisperModelInfo

/// Runtime state for a specific model variant
struct WhisperModelInfo: Identifiable {
    /// Which model size this represents
    let size: ModelSize

    /// Local file/folder path if downloaded
    var filePath: URL?

    /// Whether the model is downloaded and available on disk
    var isDownloaded: Bool

    /// Whether this model is currently loaded and active
    var isActive: Bool

    /// Whether this model is supported on the current device (per WhisperKit recommendation)
    var isSupported: Bool

    /// Download progress (0.0 to 1.0), nil when not downloading
    var downloadProgress: Double?

    /// Whether this model is currently being loaded into memory
    var isLoading: Bool = false

    var id: String { size.id }

    /// Human-readable status description
    var statusDescription: String {
        if isActive { return "Active" }
        if let progress = downloadProgress {
            return "Downloading (\(Int(progress * 100))%)"
        }
        if isDownloaded { return "Downloaded" }
        return "Not Downloaded"
    }

    /// SF Symbol name for the status icon
    var statusIconName: String {
        if isActive { return "checkmark.circle.fill" }
        if downloadProgress != nil { return "arrow.down.circle" }
        if isDownloaded { return "checkmark.circle" }
        return "arrow.down.to.line"
    }
}
