// ModelTests.swift
// VocaMac Tests
//
// Tests for data models: SystemInfo, ModelSize, ModelManager,
// WhisperModelInfo, TranscriptionResult, AppStatus, ActivationMode.

import XCTest
import ServiceManagement
@testable import VocaMac

// MARK: - SystemInfo Tests

final class SystemInfoTests: XCTestCase {

    func testDetectSystemCapabilities() {
        let capabilities = SystemInfo.detect()
        XCTAssertGreaterThan(capabilities.physicalMemoryGB, 0)
        XCTAssertGreaterThan(capabilities.coreCount, 0)
        XCTAssertFalse(capabilities.processorName.isEmpty)
    }

    func testModelRecommendationAppleSilicon() {
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 4), .tiny)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 8), .base)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 16), .small)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 24), .medium)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 48), .medium)
    }

    func testModelRecommendationIntel() {
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 8), .tiny)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 16), .base)
        XCTAssertEqual(SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 32), .small)
    }

    func testRecommendedThreadCount() {
        let threads = SystemInfo.recommendedThreadCount
        XCTAssertGreaterThanOrEqual(threads, 2)
        XCTAssertLessThanOrEqual(threads, 8)
    }

    func testModelIdentifier() {
        XCTAssertFalse(SystemInfo.modelIdentifier.isEmpty)
    }

    func testSummaryDescription() {
        let capabilities = SystemInfo.detect()
        let summary = capabilities.summaryDescription
        XCTAssertTrue(summary.contains("Processor:"))
        XCTAssertTrue(summary.contains("Architecture:"))
        XCTAssertTrue(summary.contains("Memory:"))
        XCTAssertTrue(summary.contains("Cores:"))
        XCTAssertTrue(summary.contains("Metal:"))
        XCTAssertTrue(summary.contains("Recommended Model:"))
    }
}

// MARK: - ModelSize Tests

final class ModelSizeTests: XCTestCase {

    func testModelSizesAscendingFileSize() {
        let sizes = ModelSize.allCases.map { $0.fileSizeBytes }
        for i in 1..<sizes.count {
            XCTAssertGreaterThan(sizes[i], sizes[i - 1])
        }
    }

    func testFileSizeDescription() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.fileSizeDescription.isEmpty)
        }
    }

    func testDisplayNames() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.displayName.isEmpty)
        }
    }

    func testRAMRequirementsIncreasing() {
        let rams = ModelSize.allCases.map { $0.ramRequiredGB }
        for i in 1..<rams.count {
            XCTAssertGreaterThanOrEqual(rams[i], rams[i - 1])
        }
    }

    func testQualityDescriptions() {
        for size in ModelSize.allCases {
            XCTAssertFalse(size.qualityDescription.isEmpty)
        }
    }

    func testRelativeSpeedIncreasing() {
        let speeds = ModelSize.allCases.map { $0.relativeSpeed }
        for i in 1..<speeds.count {
            XCTAssertGreaterThan(speeds[i], speeds[i - 1])
        }
    }

    func testAllCasesCount() {
        XCTAssertEqual(ModelSize.allCases.count, 5)
    }

    func testRawValues() {
        XCTAssertEqual(ModelSize.tiny.rawValue, "tiny")
        XCTAssertEqual(ModelSize.base.rawValue, "base")
        XCTAssertEqual(ModelSize.small.rawValue, "small")
        XCTAssertEqual(ModelSize.medium.rawValue, "medium")
        XCTAssertEqual(ModelSize.largeV3.rawValue, "large-v3")
    }
}

// MARK: - ModelManager Tests

final class ModelManagerTests: XCTestCase {
    /// Matches ModelManager's real modelStorageBase layout:
    /// ~/Library/Application Support/VocaMac/models/models/argmaxinc/whisperkit-coreml
    private var modelStorageBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VocaMac/models/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    override func tearDownWithError() throws {
        let vocamacRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VocaMac", isDirectory: true)
        if FileManager.default.fileExists(atPath: vocamacRoot.path) {
            try FileManager.default.removeItem(at: vocamacRoot)
        }
        try super.tearDownWithError()
    }

    func testWhisperKitModelNames() {
        let manager = ModelManager()
        XCTAssertEqual(manager.whisperKitModelName(for: .tiny), "openai_whisper-tiny")
        XCTAssertEqual(manager.whisperKitModelName(for: .base), "openai_whisper-base")
        XCTAssertEqual(manager.whisperKitModelName(for: .small), "openai_whisper-small")
        XCTAssertEqual(manager.whisperKitModelName(for: .medium), "openai_whisper-medium")
        XCTAssertEqual(manager.whisperKitModelName(for: .largeV3), "openai_whisper-large-v3")
    }

    func testDownloadedModelsReturnsArray() {
        let manager = ModelManager()
        let downloaded = manager.downloadedModels()
        XCTAssertGreaterThanOrEqual(downloaded.count, 0)
    }

    func testDiskUsageDescriptionNotEmpty() {
        let manager = ModelManager()
        XCTAssertFalse(manager.diskUsageDescription().isEmpty)
    }

    func testTotalDiskUsageNonNegative() {
        let manager = ModelManager()
        XCTAssertGreaterThanOrEqual(manager.totalDiskUsage(), 0)
    }

    func testDeleteModelRemovesInstalledDirectory() throws {
        let manager = ModelManager()
        let modelName = manager.whisperKitModelName(for: .tiny)
        let modelDir = modelStorageBase.appendingPathComponent(modelName, isDirectory: true)

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelDir.path))

        try manager.deleteModel(.tiny)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path),
            "deleteModel should remove the model directory at the installed path")
    }

    func testDeleteModelIsNoOpWhenDirectoryMissing() throws {
        let manager = ModelManager()
        // Should not throw when model was never downloaded
        XCTAssertNoThrow(try manager.deleteModel(.base))
    }
}

// MARK: - WhisperModelInfo Tests

final class WhisperModelInfoTests: XCTestCase {

    func testStatusDescription() {
        var model = WhisperModelInfo(
            size: .tiny, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.statusDescription, "Not Downloaded")

        model.isDownloaded = true
        XCTAssertEqual(model.statusDescription, "Downloaded")

        model.isActive = true
        XCTAssertEqual(model.statusDescription, "Active")

        model.isActive = false
        model.downloadProgress = 0.5
        XCTAssertEqual(model.statusDescription, "Downloading (50%)")
    }

    func testLoadingState() {
        var model = WhisperModelInfo(
            size: .base, filePath: nil, isDownloaded: true,
            isActive: false, isSupported: true
        )
        model.isLoading = true
        XCTAssertEqual(model.statusDescription, "Loading…")
        XCTAssertEqual(model.statusIconName, "arrow.trianglehead.2.clockwise")
    }

    func testDefaultIsLoading() {
        let model = WhisperModelInfo(
            size: .tiny, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertFalse(model.isLoading)
    }

    func testStatusIcon() {
        var model = WhisperModelInfo(
            size: .base, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.statusIconName, "arrow.down.to.line")

        model.isDownloaded = true
        XCTAssertEqual(model.statusIconName, "checkmark.circle")

        model.isActive = true
        XCTAssertEqual(model.statusIconName, "checkmark.circle.fill")

        model.isActive = false
        model.downloadProgress = 0.3
        XCTAssertEqual(model.statusIconName, "arrow.down.circle")
    }

    func testIDMatchesSize() {
        let model = WhisperModelInfo(
            size: .small, filePath: nil, isDownloaded: false,
            isActive: false, isSupported: true
        )
        XCTAssertEqual(model.id, "small")
    }
}

// MARK: - TranscriptionResult Tests

final class VocaTranscriptionTests: XCTestCase {

    func testCreationPreservesValues() {
        let result = VocaTranscription(
            text: "Hello world", duration: 1.5,
            detectedLanguage: "en", audioLengthSeconds: 3.0, modelUsed: .tiny
        )
        XCTAssertEqual(result.text, "Hello world")
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertEqual(result.detectedLanguage, "en")
        XCTAssertEqual(result.audioLengthSeconds, 3.0)
        XCTAssertEqual(result.modelUsed, .tiny)
    }

    func testUniqueID() {
        let r1 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: .tiny
        )
        let r2 = VocaTranscription(
            text: "Hello", duration: 1.0,
            detectedLanguage: "en", audioLengthSeconds: 2.0, modelUsed: .tiny
        )
        XCTAssertNotEqual(r1.id, r2.id)
    }
}

// MARK: - AppStatus Tests

final class AppStatusTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(AppStatus.idle.rawValue, "idle")
        XCTAssertEqual(AppStatus.recording.rawValue, "recording")
        XCTAssertEqual(AppStatus.processing.rawValue, "processing")
        XCTAssertEqual(AppStatus.error.rawValue, "error")
    }
}

// MARK: - ActivationMode Tests

final class ActivationModeTests: XCTestCase {

    func testDisplayNames() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
        }
    }

    func testDescriptions() {
        for mode in ActivationMode.allCases {
            XCTAssertFalse(mode.description.isEmpty)
        }
    }

    func testActivationModeCaseCount() {
        XCTAssertEqual(ActivationMode.allCases.count, 2)
    }

    func testRawValues() {
        XCTAssertEqual(ActivationMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(ActivationMode.doubleTapToggle.rawValue, "doubleTapToggle")
    }
}

