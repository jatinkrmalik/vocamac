// LocalLLMPostProcessorTests.swift
// VocaMac Tests

import XCTest
@testable import VocaMac

final class LocalLLMPostProcessorTests: XCTestCase {
    func testPromptIncludesTranscriptAndInstructions() {
        let prompt = LocalLLMPostProcessor.prompt(
            for: "um let's email Namrata about the launch",
            instructions: "Keep it concise."
        )

        XCTAssertTrue(prompt.contains("Keep it concise."))
        XCTAssertTrue(prompt.contains("um let's email Namrata about the launch"))
        XCTAssertTrue(prompt.contains("Return only the rewritten text."))
    }

    func testCleanedOutputRemovesPromptAndThinkingBlock() {
        let prompt = "Prompt:"
        let output = """
        \u{001B}[32mPrompt:<think>
        hidden reasoning
        </think>
        Email Namrata about the launch.
        """

        XCTAssertEqual(
            LocalLLMPostProcessor.cleanedOutput(output, prompt: prompt),
            "Email Namrata about the launch."
        )
    }

    func testModelArgumentsUseHuggingFaceReferenceForCatalogModel() throws {
        let config = TextPostProcessingConfiguration(
            runnerPath: "/usr/bin/false",
            modelID: "gemma-3-1b-q4",
            customModelPath: "",
            instructions: ""
        )

        XCTAssertEqual(
            try LocalLLMPostProcessor.modelArguments(for: config),
            ["-hf", "ggml-org/gemma-3-1b-it-GGUF:Q4_K_M", "--jinja"]
        )
    }

    func testModelArgumentsValidateCustomModelPath() {
        let config = TextPostProcessingConfiguration(
            runnerPath: "/usr/bin/false",
            modelID: LocalLLMModel.customID,
            customModelPath: "/definitely/not/a/model.gguf",
            instructions: ""
        )

        XCTAssertThrowsError(try LocalLLMPostProcessor.modelArguments(for: config))
    }

    func testDetectedRunnerPathUsesFirstExecutableCandidate() {
        XCTAssertEqual(
            LocalLLMPostProcessor.detectedRunnerPath(in: ["/definitely/missing", "/bin/echo"]),
            "/bin/echo"
        )
    }
}
