// VocaMacTests.swift
// VocaMac Tests
//
// Unit tests for VocaMac core services.
// These tests require Xcode to run (XCTest framework).
// Run with: xcodebuild test -scheme VocaMac -destination 'platform=macOS'

import Testing
@testable import VocaMac

// MARK: - SystemInfo Tests

@Suite("SystemInfo Tests")
struct SystemInfoTests {

    @Test("Detect system capabilities returns valid values")
    func detectSystemCapabilities() {
        let capabilities = SystemInfo.detect()

        #expect(capabilities.physicalMemoryGB > 0)
        #expect(capabilities.coreCount > 0)
        #expect(!capabilities.processorName.isEmpty)
    }

    @Test("Model recommendation for Apple Silicon")
    func modelRecommendationAppleSilicon() {
        let model4GB = SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 4)
        #expect(model4GB == .tiny)

        let model8GB = SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 8)
        #expect(model8GB == .base)

        let model16GB = SystemInfo.recommendModel(isAppleSilicon: true, memoryGB: 16)
        #expect(model16GB == .small)
    }

    @Test("Model recommendation for Intel")
    func modelRecommendationIntel() {
        let model8GB = SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 8)
        #expect(model8GB == .tiny)

        let model16GB = SystemInfo.recommendModel(isAppleSilicon: false, memoryGB: 16)
        #expect(model16GB == .base)
    }

    @Test("Recommended thread count is within bounds")
    func recommendedThreadCount() {
        let threads = SystemInfo.recommendedThreadCount
        #expect(threads >= 2)
        #expect(threads <= 8)
    }
}

// MARK: - ModelSize Tests

@Suite("ModelSize Tests")
struct ModelSizeTests {

    @Test("All model sizes have valid file names")
    func allModelSizesHaveFileNames() {
        for size in ModelSize.allCases {
            #expect(!size.fileName.isEmpty)
            #expect(size.fileName.hasPrefix("ggml-"))
            #expect(size.fileName.hasSuffix(".bin"))
        }
    }

    @Test("Model sizes are in ascending order by file size")
    func modelSizesAreOrdered() {
        let sizes = ModelSize.allCases.map { $0.fileSizeBytes }
        for i in 1..<sizes.count {
            #expect(sizes[i] > sizes[i - 1], "Model sizes should be in ascending order")
        }
    }

    @Test("File size description is not empty")
    func fileSizeDescription() {
        let description = ModelSize.tiny.fileSizeDescription
        #expect(!description.isEmpty)
    }

    @Test("All models have display names")
    func displayNames() {
        for size in ModelSize.allCases {
            #expect(!size.displayName.isEmpty)
        }
    }

    @Test("RAM requirements increase with model size")
    func ramRequirements() {
        let rams = ModelSize.allCases.map { $0.ramRequiredGB }
        for i in 1..<rams.count {
            #expect(rams[i] >= rams[i - 1], "RAM requirements should increase with model size")
        }
    }
}

// MARK: - WhisperModelInfo Tests

@Suite("WhisperModelInfo Tests")
struct WhisperModelInfoTests {

    @Test("Status description reflects state correctly")
    func statusDescription() {
        var model = WhisperModelInfo(
            size: .tiny,
            filePath: nil,
            isDownloaded: false,
            isActive: false,
            isSupported: true
        )
        #expect(model.statusDescription == "Not Downloaded")

        model.isDownloaded = true
        #expect(model.statusDescription == "Downloaded")

        model.isActive = true
        #expect(model.statusDescription == "Active")

        model.isActive = false
        model.downloadProgress = 0.5
        #expect(model.statusDescription == "Downloading (50%)")
    }

    @Test("Status icon reflects state")
    func statusIcon() {
        var model = WhisperModelInfo(
            size: .base,
            filePath: nil,
            isDownloaded: false,
            isActive: false,
            isSupported: true
        )
        #expect(model.statusIconName == "arrow.down.to.line")

        model.isDownloaded = true
        #expect(model.statusIconName == "checkmark.circle")

        model.isActive = true
        #expect(model.statusIconName == "checkmark.circle.fill")
    }
}

// MARK: - TranscriptionResult Tests

@Suite("VocaTranscription Tests")
struct VocaTranscriptionTests {

    @Test("VocaTranscription creation preserves values")
    func vocaTranscriptionCreation() {
        let result = VocaTranscription(
            text: "Hello world",
            duration: 1.5,
            detectedLanguage: "en",
            audioLengthSeconds: 3.0,
            modelUsed: .tiny
        )

        #expect(result.text == "Hello world")
        #expect(result.duration == 1.5)
        #expect(result.detectedLanguage == "en")
        #expect(result.audioLengthSeconds == 3.0)
        #expect(result.modelUsed == .tiny)
    }
}

// MARK: - KeyCodeReference Tests

@Suite("KeyCodeReference Tests")
struct KeyCodeReferenceTests {

    @Test("Common hotkeys list is not empty")
    func commonHotKeysNotEmpty() {
        #expect(!KeyCodeReference.commonHotKeys.isEmpty)
    }

    @Test("Display name for Right Option key code")
    func displayNameForKnownKeyCode() {
        let name = KeyCodeReference.displayName(for: 61)
        #expect(name == "Right Option (⌥)")
    }

    @Test("Display name for unknown key code falls back gracefully")
    func displayNameForUnknownKeyCode() {
        let name = KeyCodeReference.displayName(for: 999)
        #expect(name == "Key 999")
    }
}
